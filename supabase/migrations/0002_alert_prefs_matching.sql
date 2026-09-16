-- FindIt: make matching/notifications respect each user's Alert Radius
-- settings (radius_km, categories, push_enabled, ai_only).
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run (create or replace).

create or replace function public.findit_score_new_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate record;
  computed_score int;
  lost_id uuid;
  found_id uuid;
  owner_id uuid;
  owner_lat double precision;
  owner_lng double precision;
  prefs record;
  distance_km double precision;
  should_notify boolean;
  min_score_for_notify int;
begin
  if new.status = 'lost' then
    owner_id := new.user_id;
    owner_lat := new.lat;
    owner_lng := new.lng;
    select * into prefs from public.alert_prefs where user_id = owner_id;

    for candidate in
      select * from public.items
      where status = 'found' and coalesce(returned,false) = false and id <> new.id
    loop
      computed_score := least(99, round(
        similarity(coalesce(new.title,''), coalesce(candidate.title,'')) * 70
        + case when new.category is not null and new.category = candidate.category then 25 else 0 end
      )::int);
      if computed_score >= 30 then
        lost_id := new.id;
        found_id := candidate.id;
        insert into public.item_matches (lost_item_id, found_item_id, score)
        values (lost_id, found_id, computed_score)
        on conflict (lost_item_id, found_item_id) do update set score = excluded.score;

        -- Decide whether this also warrants a proactive notification, based
        -- on the lost item owner's Alert Radius preferences. The match row
        -- above is always recorded regardless, so Possible Matches still
        -- shows everything when the user browses it themselves.
        should_notify := true;
        min_score_for_notify := 60;

        if prefs is not null then
          if prefs.push_enabled = false then
            should_notify := false;
          end if;

          if should_notify and array_length(prefs.categories, 1) is not null
             and candidate.category is not null
             and not (candidate.category = any(prefs.categories)) then
            should_notify := false;
          end if;

          if should_notify and owner_lat is not null and owner_lng is not null
             and candidate.lat is not null and candidate.lng is not null then
            distance_km := 6371 * acos(
              least(1.0, greatest(-1.0,
                cos(radians(owner_lat)) * cos(radians(candidate.lat)) * cos(radians(candidate.lng) - radians(owner_lng))
                + sin(radians(owner_lat)) * sin(radians(candidate.lat))
              ))
            );
            if distance_km > prefs.radius_km then
              should_notify := false;
            end if;
          end if;

          if prefs.ai_only = true then
            min_score_for_notify := 80;
          end if;
        end if;

        if should_notify and computed_score >= min_score_for_notify then
          insert into public.notifications (user_id, type, title, body, related_item_id)
          values (owner_id, 'match', 'Possible match found',
                  'We found a ' || computed_score || '% match for your report "' || new.title || '"', new.id);
        end if;
      end if;
    end loop;

  elsif new.status = 'found' then
    for candidate in
      select * from public.items
      where status = 'lost' and coalesce(returned,false) = false and id <> new.id
    loop
      computed_score := least(99, round(
        similarity(coalesce(new.title,''), coalesce(candidate.title,'')) * 70
        + case when new.category is not null and new.category = candidate.category then 25 else 0 end
      )::int);
      if computed_score >= 30 then
        lost_id := candidate.id;
        found_id := new.id;
        owner_id := candidate.user_id;
        owner_lat := candidate.lat;
        owner_lng := candidate.lng;
        select * into prefs from public.alert_prefs where user_id = owner_id;

        insert into public.item_matches (lost_item_id, found_item_id, score)
        values (lost_id, found_id, computed_score)
        on conflict (lost_item_id, found_item_id) do update set score = excluded.score;

        should_notify := true;
        min_score_for_notify := 60;

        if prefs is not null then
          if prefs.push_enabled = false then
            should_notify := false;
          end if;

          if should_notify and array_length(prefs.categories, 1) is not null
             and new.category is not null
             and not (new.category = any(prefs.categories)) then
            should_notify := false;
          end if;

          if should_notify and owner_lat is not null and owner_lng is not null
             and new.lat is not null and new.lng is not null then
            distance_km := 6371 * acos(
              least(1.0, greatest(-1.0,
                cos(radians(owner_lat)) * cos(radians(new.lat)) * cos(radians(new.lng) - radians(owner_lng))
                + sin(radians(owner_lat)) * sin(radians(new.lat))
              ))
            );
            if distance_km > prefs.radius_km then
              should_notify := false;
            end if;
          end if;

          if prefs.ai_only = true then
            min_score_for_notify := 80;
          end if;
        end if;

        if should_notify and computed_score >= min_score_for_notify then
          insert into public.notifications (user_id, type, title, body, related_item_id)
          values (owner_id, 'match', 'Possible match found',
                  'We found a ' || computed_score || '% match for your report "' || candidate.title || '"', candidate.id);
        end if;
      end if;
    end loop;
  end if;
  return new;
end;
$$;
