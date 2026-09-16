// lib/screens/filters_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SearchFilters {
  String? category;
  double distanceKm;
  DateTime? from;
  DateTime? to;
  String status; // open | resolved | all
  String sortBy; // newest | oldest

  SearchFilters({
    this.category,
    this.distanceKm = 5,
    this.from,
    this.to,
    this.status = 'open',
    this.sortBy = 'newest',
  });

  SearchFilters copy() => SearchFilters(
    category: category,
    distanceKm: distanceKm,
    from: from,
    to: to,
    status: status,
    sortBy: sortBy,
  );

  int get activeCount {
    var n = 0;
    if (category != null) n++;
    if (distanceKm != 5) n++;
    if (from != null || to != null) n++;
    if (status != 'open') n++;
    return n;
  }
}

/// Opens the filters sheet and returns the chosen filters, or null if cancelled.
Future<SearchFilters?> showFiltersSheet(
  BuildContext context,
  SearchFilters current,
) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _FiltersSheet(initial: current.copy()),
    ),
  );
}

class _FiltersSheet extends StatefulWidget {
  final SearchFilters initial;
  const _FiltersSheet({required this.initial});

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late SearchFilters f = widget.initial;

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? f.from : f.to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          f.from = picked;
        } else {
          f.to = picked;
        }
      });
    }
  }

  String _fmt(DateTime? d) => d == null ? 'Any' : '${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Filters',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: kItemCategories
                        .map(
                          (c) => CategoryChip(
                            label: c,
                            selected: f.category == c,
                            onTap: () => setState(
                              () => f.category = f.category == c ? null : c,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Text(
                        'Distance',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${f.distanceKm.round()} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary500,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: f.distanceKm,
                    min: 1,
                    max: 25,
                    divisions: 24,
                    activeColor: AppColors.primary500,
                    onChanged: (v) => setState(() => f.distanceKm = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        '1 km',
                        style: TextStyle(
                          color: AppColors.neutralGrey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '25 km',
                        style: TextStyle(
                          color: AppColors.neutralGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Date Range',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                          ),
                          label: Text(_fmt(f.from)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                          ),
                          label: Text(_fmt(f.to)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CategoryChip(
                        label: 'Open',
                        selected: f.status == 'open',
                        onTap: () => setState(() => f.status = 'open'),
                      ),
                      const SizedBox(width: 10),
                      CategoryChip(
                        label: 'Resolved',
                        selected: f.status == 'resolved',
                        onTap: () => setState(() => f.status = 'resolved'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Sort By',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: f.sortBy,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'newest',
                            child: Text('Newest first'),
                          ),
                          DropdownMenuItem(
                            value: 'oldest',
                            child: Text('Oldest first'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => f.sortBy = v ?? 'newest'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => f = SearchFilters()),
                  child: const Text('Clear all'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, f),
                    child: const Text('Show Results'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
