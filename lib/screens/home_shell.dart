// lib/screens/home_shell.dart
import 'package:flutter/material.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'post_item_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    ChatListScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    PushService.init();
  }

  void _openReportItem() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PostItemScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tablet/Chromebook/large-window: a bottom bar squeezed into the corner
    // of a wide screen is exactly what Android's own large-screen app
    // guidelines call out as a mistake — it becomes a side NavigationRail
    // instead, which is the standard adaptive pattern (see e.g. Gmail,
    // YouTube on ChromeOS/tablets). Phones are completely unaffected: below
    // the tablet breakpoint this returns the original bottom-pill layout.
    if (isWideScreen(context)) {
      return Scaffold(
        body: Row(
          children: [
            _sideRail(),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: _screens),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // The nav bar is fixed in Scaffold.bottomNavigationBar (never scrolls
      // with the body) and drawn as a floating rounded pill with margin from
      // the screen edges, so content can scroll all the way to the bottom
      // edge behind it rather than stopping at a hard, full-width bar.
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _navItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  index: 0,
                ),
                _navItem(
                  icon: Icons.search,
                  activeIcon: Icons.search,
                  label: 'Search',
                  index: 1,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _openReportItem,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.primary500,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                _navItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: 'Chat',
                  index: 2,
                ),
                _navItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profile',
                  index: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideRail() {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      backgroundColor: Colors.white,
      labelType: NavigationRailLabelType.all,
      minWidth: 84,
      selectedIconTheme: const IconThemeData(color: AppColors.primary500),
      selectedLabelTextStyle: const TextStyle(
        color: AppColors.primary500,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      unselectedIconTheme: const IconThemeData(color: AppColors.neutralGrey),
      unselectedLabelTextStyle: const TextStyle(
        color: AppColors.neutralGrey,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: FloatingActionButton(
          onPressed: _openReportItem,
          backgroundColor: AppColors.primary500,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Home'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.search),
          label: Text('Search'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: Text('Chat'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: Text('Profile'),
        ),
      ],
    );
  }

  Widget _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final active = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active ? AppColors.primary500 : AppColors.neutralGrey,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primary500 : AppColors.neutralGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
