import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../models/meal_plan.dart';
import '../services/gemini_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/common_widgets.dart';
import 'finances_screen.dart';

class ManagementHubScreen extends StatefulWidget {
  const ManagementHubScreen({super.key});

  @override
  State<ManagementHubScreen> createState() => _ManagementHubScreenState();
}

class _ManagementHubScreenState extends State<ManagementHubScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return RodMaePageFrame(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: SegmentedSwitcher(
              labels: const ['Finances', 'Meal Slots'],
              icons: const [
                Icons.account_balance_wallet_outlined,
                Icons.calendar_month_outlined,
              ],
              selected: _tab,
              onSelected: (value) => setState(() => _tab = value),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                FinanceManagementTab(),
                MealsAutomationTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MealsAutomationTab extends StatefulWidget {
  const MealsAutomationTab({super.key});

  @override
  State<MealsAutomationTab> createState() => _MealsAutomationTabState();
}

class _MealsAutomationTabState extends State<MealsAutomationTab> {
  final _promptController =
      TextEditingController(text: 'Suggest 7-day budget newlywed Filipino meals');
  final _plan = <MealPlanDay>[];
  final _groceryItems = <GroceryChecklistItem>[];
  bool _generating = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _askAi() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _generating) {
      return;
    }
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final plan = await GeminiCompanionService.instance.generateMealPlan(prompt);
      setState(() {
        _plan.clear();
        _plan.addAll(plan);
        _groceryItems.clear();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('AI meal grid generated.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('AI meal planning failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  void _generateGroceryList() {
    if (_plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate a meal plan first.')),
      );
      return;
    }
    final ordered = <String>{};
    for (final day in _plan) {
      if (day.ingredients.isNotEmpty) {
        ordered.addAll(day.ingredients);
      } else {
        ordered.addAll([
          day.breakfast,
          day.lunch,
          day.dinner,
        ]);
      }
    }
    setState(() {
      _groceryItems
        ..clear()
        ..addAll(ordered.map((name) => GroceryChecklistItem(name: name)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 118),
      children: [
        GlassCard(
          gradient: isDark ? RodMaeColors.getCardGradient(isDark) : null,
          borderColor: RodMaeColors.electricBlue.withValues(alpha: 0.2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: RodMaeColors.sky),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Ask AI Companion',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _promptController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Suggest 7-day newlywed Filipino budget meals',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: PrimaryPillButton(
                      label: 'Generate Meals',
                      icon: Icons.restaurant_menu_rounded,
                      busy: _generating,
                      onPressed: _askAi,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PrimaryPillButton(
                      label: 'Grocery List',
                      icon: Icons.checklist_rounded,
                      color: RodMaeColors.mint,
                      onPressed: _generateGroceryList,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader(
          title: 'SPOUSE NUTRITIONAL PLANNER',
          icon: Icons.calendar_month_rounded,
          trailing: 'AI ASSISTED',
        ),
        if (_plan.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                'No nutritional menu generated yet.\nTap "Generate Meals" to request Gemini AI recipes!',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white30 : Colors.black26,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          )
        else
          GridView.builder(
            itemCount: _plan.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, index) {
              return MealDayCard(day: _plan[index]);
            },
          ),
        if (_groceryItems.isNotEmpty) ...[
          SectionHeader(
            title: 'GROCERY CHECKLIST',
            icon: Icons.shopping_bag_outlined,
            trailing: '${_groceryItems.where((item) => item.checked).length}/${_groceryItems.length}',
          ),
          ...List.generate(_groceryItems.length, (index) {
            final item = _groceryItems[index];
            return GroceryChecklistTile(
              item: item,
              onChanged: (value) {
                setState(() => item.checked = value);
              },
            );
          }),
        ],
      ],
    );
  }
}

class MealDayCard extends StatelessWidget {
  final MealPlanDay day;

  const MealDayCard({
    required this.day,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderColor: RodMaeColors.sky.withValues(alpha: isDark ? 0.08 : 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${day.day} Menu',
            style: GoogleFonts.inter(
              color: RodMaeColors.electricBlue,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _MealLine(label: 'Breakfast', value: day.breakfast),
          _MealLine(label: 'Lunch', value: day.lunch),
          _MealLine(label: 'Dinner', value: day.dinner),
        ],
      ),
    );
  }
}

class _MealLine extends StatelessWidget {
  final String label;
  final String value;

  const _MealLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class GroceryChecklistTile extends StatelessWidget {
  final GroceryChecklistItem item;
  final ValueChanged<bool> onChanged;

  const GroceryChecklistTile({
    required this.item,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
      child: CheckboxListTile(
        value: item.checked,
        onChanged: (value) => onChanged(value ?? false),
        title: Text(
          item.name,
          style: GoogleFonts.inter(
            color: item.checked 
                ? (isDark ? Colors.white38 : Colors.black26) 
                : (isDark ? Colors.white : RodMaeColors.lightText),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            decoration: item.checked ? TextDecoration.lineThrough : null,
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: RodMaeColors.mint,
      ),
    );
  }
}
