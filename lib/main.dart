import 'package:glyphxtools/pages/converters_page.dart';
import 'package:glyphxtools/pages/meg_viewer_page.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const GlyphXToolsApp());
}

class GlyphXToolsApp extends StatelessWidget {
  const GlyphXToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlyphX Tools',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainPage(),
    );
  }
}

// ==========================================
// PAGE MODEL
// ==========================================

class AppPage {
  const AppPage({
    required this.title,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

// ==========================================
// MAIN PAGE / NAVIGATION
// ==========================================

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  // Add new pages here.
  late final List<AppPage> _pages = [
    AppPage(
      title: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      page: const HomePage(),
    ),
    AppPage(
      title: 'MEG Viewer',
      icon: Icons.archive_outlined,
      selectedIcon: Icons.archive,
      page: const MegViewerPage(),
    ),
    AppPage(
      title: 'Converters',
      icon: Icons.transform,
      selectedIcon: Icons.transform,
      page: const ConvertersPage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 700;

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (isDesktop)
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (int index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    labelType: NavigationRailLabelType.all,
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Icon(Icons.widgets_rounded, size: 32),
                    ),
                    destinations: _pages.map((AppPage page) {
                      return NavigationRailDestination(
                        icon: Icon(page.icon),
                        selectedIcon: Icon(page.selectedIcon),
                        label: Text(page.title),
                      );
                    }).toList(),
                  ),

                if (isDesktop) const VerticalDivider(width: 1),

                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(context),

                      const Divider(height: 1),

                      Expanded(
                        child: IndexedStack(
                          index: _selectedIndex,
                          children: _pages.map((AppPage page) {
                            return page.page;
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  destinations: _pages.map((AppPage page) {
                    return NavigationDestination(
                      icon: Icon(page.icon),
                      selectedIcon: Icon(page.selectedIcon),
                      label: page.title,
                    );
                  }).toList(),
                ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          Text(
            'GlyphX Tools',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            _pages[_selectedIndex].title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// HOME PAGE
// ==========================================

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.widgets_rounded,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome to GlyphX Tools',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Your collection of useful tools.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TOOLS PAGE
// ==========================================

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Your tools will appear here.'));
  }
}

// ==========================================
// SETTINGS PAGE
// ==========================================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Settings'));
  }
}
