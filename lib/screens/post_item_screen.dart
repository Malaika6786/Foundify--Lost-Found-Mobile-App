// lib/screens/post_item_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ad_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/friendly_error.dart';
import 'possible_matches_screen.dart';

class PostItemScreen extends StatefulWidget {
  const PostItemScreen({super.key});
  @override
  State<PostItemScreen> createState() => _PostItemScreenState();
}

class _PostItemScreenState extends State<PostItemScreen> {
  final title = TextEditingController();
  final description = TextEditingController();
  final rewardController = TextEditingController();
  final customCategoryController = TextEditingController();
  bool rewardEnabled = false;

  String status = 'lost'; // lost | found
  String category = kItemCategories.first;

  Uint8List? imgBytes;
  final List<Uint8List> imgBytesList = [];

  Position? pos;
  bool saving = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Interstitials must be pre-loaded before they can be shown — starting
    // the load now means one is very likely ready by the time the user
    // finishes filling out the form and actually submits it.
    AdService.loadInterstitialAd();
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    rewardController.dispose();
    customCategoryController.dispose();
    super.dispose();
  }

  // Modern phone cameras shoot 12MP+ photos; `imageQuality` alone only
  // controls JPEG compression, not pixel dimensions, so an "80% quality"
  // photo can still be several MB. Capping the dimensions here is what
  // actually fixes slow uploads and slow feed-scrolling downloads for
  // everyone — 1600px is plenty for a phone screen at any zoom level.
  static const _maxImageDimension = 1600.0;

  Future<void> pickImages() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: _maxImageDimension,
        maxHeight: _maxImageDimension,
      );
      if (files.isNotEmpty) {
        for (final f in files) {
          imgBytesList.add(await f.readAsBytes());
        }
        imgBytes = imgBytesList.isNotEmpty ? imgBytesList.first : null;
        setState(() {});
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> captureImage() async {
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: _maxImageDimension,
      maxHeight: _maxImageDimension,
    );
    if (f != null) {
      imgBytesList.add(await f.readAsBytes());
      imgBytes = imgBytesList.isNotEmpty ? imgBytesList.first : null;
      setState(() {});
    }
  }

  void removeImageAt(int index) {
    if (index < 0 || index >= imgBytesList.length) return;
    imgBytesList.removeAt(index);
    imgBytes = imgBytesList.isNotEmpty ? imgBytesList.first : null;
    setState(() {});
  }

  Future<void> getLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied permanently')),
      );
      return;
    }
    pos = await Geolocator.getCurrentPosition();
    setState(() {});
  }

  Future<void> submit() async {
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a title')));
      return;
    }

    double? rewardValue;
    if (rewardEnabled && status == 'lost') {
      final text = rewardController.text.trim();
      rewardValue = double.tryParse(text);
      if (text.isEmpty || rewardValue == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid reward number')),
        );
        return;
      }
    }

    String finalCategory = category;
    if (category == 'Other') {
      final custom = customCategoryController.text.trim();
      if (custom.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a category name')));
        return;
      }
      finalCategory = custom;
    }

    setState(() => saving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not logged in')));
        return;
      }

      List<String> uploadedUrls = [];
      if (imgBytesList.isNotEmpty) {
        uploadedUrls = await SupabaseService.uploadMultipleImages(
          imgBytesList,
          directoryPrefix: 'items/${user.id}',
        );
      }
      final firstUrl = uploadedUrls.isNotEmpty ? uploadedUrls.first : null;

      final profile = await SupabaseService.getProfile(user.id);
      final username = profile?['username'] as String?;
      final avatarUrl = profile?['avatar_url'] as String?;

      final newItemId = await SupabaseService.createItem(
        title: title.text.trim(),
        description: description.text.trim(),
        status: status,
        imageUrl: firstUrl,
        imageUrls: uploadedUrls.isEmpty ? null : uploadedUrls,
        reward: rewardValue,
        lat: pos?.latitude,
        lng: pos?.longitude,
        userId: user.id,
        username: username,
        avatarUrl: avatarUrl,
        category: finalCategory,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item posted successfully')));
      AdService.showInterstitialAdIfLoaded();

      if (status == 'lost') {
        // Server-side trigger already scored this report against open found
        // items — show whatever it found.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PossibleMatchesScreen(lostItemId: newItemId),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Report Item'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: ResponsiveCenter(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PillTabBar(
              items: [
                PillTabItem(
                  label: 'I Lost This',
                  selected: status == 'lost',
                  activeColor: AppColors.error500,
                  onTap: () => setState(() => status = 'lost'),
                ),
                PillTabItem(
                  label: 'I Found This',
                  selected: status == 'found',
                  activeColor: AppColors.success500,
                  onTap: () => setState(() => status = 'found'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionLabel('Photos'),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...imgBytesList.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              e.value,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: GestureDetector(
                              onTap: () => removeImageAt(e.key),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      builder: (_) => SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text('Choose from gallery'),
                              onTap: () {
                                Navigator.pop(context);
                                pickImages();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text('Take a photo'),
                              onTap: () {
                                Navigator.pop(context);
                                captureImage();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: AppColors.neutralGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _sectionLabel('Title'),
            const SizedBox(height: 8),
            TextField(
              controller: title,
              decoration: const InputDecoration(
                hintText: 'e.g. Black leather wallet',
              ),
            ),
            const SizedBox(height: 20),

            _sectionLabel('Category'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: kItemCategories.map((c) {
                return _CategoryTile(
                  label: c,
                  selected: category == c,
                  onTap: () => setState(() => category = c),
                );
              }).toList(),
            ),
            if (category == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: customCategoryController,
                decoration: const InputDecoration(
                  hintText: 'Describe the category (e.g. Umbrella)',
                ),
              ),
            ],
            const SizedBox(height: 20),

            _sectionLabel('Description'),
            const SizedBox(height: 8),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'Add distinguishing details (color, marks, contents)...',
              ),
            ),
            const SizedBox(height: 20),

            _sectionLabel('Location'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: getLocation,
              child: Container(
                height: 130,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary100),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(size: Size.infinite, painter: _GridPainter()),
                    Icon(
                      Icons.location_on,
                      color: AppColors.accent500,
                      size: 36,
                    ),
                    if (pos != null)
                      Positioned(
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${pos!.latitude.toStringAsFixed(4)}, ${pos!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Tap to use my location',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (status == 'lost') ...[
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Offer a reward',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                value: rewardEnabled,
                activeThumbColor: AppColors.primary500,
                onChanged: (v) => setState(() => rewardEnabled = v),
              ),
              if (rewardEnabled)
                TextField(
                  controller: rewardController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Amount',
                    prefixText: '₨ ',
                  ),
                ),
            ],

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : submit,
                child: Text(saving ? 'Submitting…' : 'Submit Report'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
  );
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 82,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary500 : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(
              categoryIcon(label),
              color: selected ? AppColors.primary500 : AppColors.ink,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary500 : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary100
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += size.width / 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += size.height / 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
