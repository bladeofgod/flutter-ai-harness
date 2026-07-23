import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// Shoppe 五个主分支的共享导航壳，只接收导航状态与回调。
final class ShoppeMainNavigationShell extends StatelessWidget {
  const ShoppeMainNavigationShell({
    required this.child,
    required this.currentIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: child,
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 2,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const ValueKey('main-bottom-navigation'),
          height: 50,
          child: Row(
            children: [
              for (var index = 0; index < _destinations.length; index += 1)
                Expanded(
                  child: _NavigationDestination(
                    destination: _destinations[index],
                    selected: currentIndex == index,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey<String>(
      'main-navigation-semantics-${destination.label.toLowerCase()}',
    ),
    label: destination.label,
    button: true,
    selected: selected,
    child: InkResponse(
      key: ValueKey<String>(
        'main-navigation-${destination.label.toLowerCase()}',
      ),
      onTap: onTap,
      radius: 28,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 50,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                destination.icon,
                size: 25,
                color: selected ? AppColors.textPrimary : AppColors.primary,
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 9,
                height: 3,
                child: selected
                    ? const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary,
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _Destination {
  const _Destination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const _destinations = <_Destination>[
  _Destination(label: 'Shop', icon: Icons.home_outlined),
  _Destination(label: 'Wishlist', icon: Icons.favorite_border),
  _Destination(label: 'Categories', icon: Icons.receipt_long_outlined),
  _Destination(label: 'Cart', icon: Icons.shopping_bag_outlined),
  _Destination(label: 'Profile', icon: Icons.person_outline),
];
