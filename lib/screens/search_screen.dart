// lib/screens/search_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart';
import 'filters_screen.dart';
import 'item_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Item> _results = [];
  bool _loading = false;
  bool _searched = false;
  SearchFilters filters = SearchFilters();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _loading = true;
      _searched = true;
    });

    try {
      var items = await SupabaseService.fetchItems(
        category: filters.category,
        query: query.trim().isEmpty ? null : query.trim(),
      );

      if (filters.status == 'resolved') {
        items = items.where((i) => i.returned).toList();
      } else if (filters.status == 'open') {
        items = items.where((i) => !i.returned).toList();
      }

      if (filters.from != null || filters.to != null) {
        items = items.where((i) {
          final created = i.createdAt;
          if (created == null) return false;
          if (filters.from != null && created.isBefore(filters.from!)) {
            return false;
          }
          if (filters.to != null &&
              created.isAfter(filters.to!.add(const Duration(days: 1)))) {
            return false;
          }
          return true;
        }).toList();
      }

      if (filters.distanceKm != 5) {
        final origin = await _currentPositionOrNull();
        if (origin != null) {
          items = items.where((i) {
            if (i.latitude == null || i.longitude == null) return false;
            final km = _distanceKm(
              origin.latitude,
              origin.longitude,
              i.latitude!,
              i.longitude!,
            );
            return km <= filters.distanceKm;
          }).toList();
        }
      }

      if (filters.sortBy == 'oldest') {
        items = items.reversed.toList();
      }

      if (mounted) setState(() => _results = items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
      setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Best-effort current position for the distance filter — returns null
  /// (silently skipping the distance filter) if location is unavailable or
  /// permission isn't granted, rather than blocking search.
  Future<Position?> _currentPositionOrNull() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      return null;
    }
  }

  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180);

  Future<void> _openFilters() async {
    final updated = await showFiltersSheet(context, filters);
    if (updated != null) {
      setState(() => filters = updated);
      _performSearch(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _performSearch,
                      decoration: InputDecoration(
                        hintText: 'Search lost & found items...',
                        prefixIcon: const Icon(Icons.search),
                        fillColor: AppColors.neutral100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Stack(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.tune,
                            color: AppColors.primary500,
                          ),
                          onPressed: _openFilters,
                        ),
                        if (filters.activeCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.accent500,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (filters.category != null || filters.distanceKm != 5)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (filters.category != null)
                        _activeFilterChip(filters.category!, () {
                          setState(() => filters.category = null);
                          _performSearch(_controller.text);
                        }),
                      if (filters.distanceKm != 5)
                        _activeFilterChip(
                          'Within ${filters.distanceKm.round()} km',
                          () {
                            setState(() => filters.distanceKm = 5);
                            _performSearch(_controller.text);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_searched)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      '${_results.length} results',
                      style: const TextStyle(color: AppColors.neutralGrey),
                    ),
                    const Spacer(),
                    Text(
                      filters.sortBy == 'newest' ? 'Newest' : 'Oldest',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary500,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : !_searched
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search,
                            size: 56,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Search for a lost or found item',
                            style: TextStyle(color: AppColors.neutralGrey),
                          ),
                        ],
                      ),
                    )
                  : _results.isEmpty
                  ? const Center(child: Text('No results'))
                  : ListView.builder(
                      // Extra bottom padding so the last result isn't
                      // hidden behind the floating bottom nav bar
                      // (HomeShell uses extendBody: true).
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final it = _results[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ItemListCard(
                            item: it,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ItemDetailScreen(item: it),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _activeFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primary700,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close,
              size: 14,
              color: AppColors.primary700,
            ),
          ),
        ],
      ),
    );
  }
}
