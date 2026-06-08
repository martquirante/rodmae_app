import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/finance_entry.dart';
import '../models/meal_plan.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../services/gemini_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/common_widgets.dart';

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

class FinanceManagementTab extends StatefulWidget {
  const FinanceManagementTab({super.key});

  @override
  State<FinanceManagementTab> createState() => _FinanceManagementTabState();
}

class _FinanceManagementTabState extends State<FinanceManagementTab> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController(text: 'Shared');
  FinanceType _type = FinanceType.expense;
  bool _saving = false;
  bool _scanning = false;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    final title = _titleController.text.trim();
    final amount = Formatters.asDouble(_amountController.text);
    final category = _categoryController.text.trim().isEmpty
        ? 'Shared'
        : _categoryController.text.trim();
    if (title.isEmpty || amount <= 0 || _saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title and a valid amount.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await SupabaseWeddingRepository.instance.insertFinance(
        FinanceEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title,
          category: category,
          amount: amount,
          type: _type,
          date: DateTime.now(),
          createdBy: PartnerIdentity.active.value.label,
        ),
      );
      _titleController.clear();
      _amountController.clear();
      _categoryController.text = 'Shared';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finance record synced to Supabase.')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Finance sync failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _scanReceipt() async {
    if (_scanning) {
      return;
    }
    setState(() => _scanning = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 86,
      );
      if (image == null) {
        return;
      }
      final bytes = await image.readAsBytes();
      final receipt = await GeminiCompanionService.instance.scanReceipt(bytes);
      await SupabaseWeddingRepository.instance.insertReceiptExpense(receipt);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Receipt synced: ${receipt.storeName} ${Formatters.compactMoney(receipt.totalAmount)}',
          ),
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI receipt scan failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        StreamBuilder<List<FinanceEntry>>(
          stream: SupabaseWeddingRepository.instance.watchFinances(),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? <FinanceEntry>[];
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 122),
              children: [
                FinanceFlipCard(entries: entries),
                const SectionHeader(
                  title: 'ADD A NEW TRANSACTION',
                  icon: Icons.add_card_rounded,
                  trailing: 'Shared Account',
                ),
                _FinanceEntryForm(
                  titleController: _titleController,
                  amountController: _amountController,
                  categoryController: _categoryController,
                  type: _type,
                  saving: _saving,
                  onTypeChanged: (type) => setState(() => _type = type),
                  onSubmit: _addEntry,
                ),
                const SectionHeader(
                  title: 'TRANSACTION HISTORY',
                  icon: Icons.receipt_long_rounded,
                ),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No transactions recorded yet.\nFill in the form above to add one!',
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
                  ...entries.map(FinanceLedgerTile.new),
              ],
            );
          },
        ),
        Positioned(
          right: 18,
          bottom: 100,
          child: FloatingActionButton.extended(
            onPressed: _scanning ? null : _scanReceipt,
            backgroundColor: RodMaeColors.gold,
            foregroundColor: RodMaeColors.navy,
            icon: _scanning
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_rounded),
            label: Text(
              _scanning ? 'Scanning' : 'AI Receipt Scanner',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class FinanceFlipCard extends StatefulWidget {
  final List<FinanceEntry> entries;

  const FinanceFlipCard({
    required this.entries,
    super.key,
  });

  @override
  State<FinanceFlipCard> createState() => _FinanceFlipCardState();
}

class _FinanceFlipCardState extends State<FinanceFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (widget.entries.isEmpty) return;
    if (_controller.value < 0.5) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final income = widget.entries
        .where((entry) => entry.type == FinanceType.income)
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final expenses = widget.entries
        .where((entry) => entry.type == FinanceType.expense)
        .fold<double>(0, (sum, entry) => sum + entry.amount);
    final savingsProgress = income == 0 ? 0.0 : ((income - expenses) / income);

    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final angle = _animation.value * math.pi;
          final showFront = angle < math.pi / 2;
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(angle),
            alignment: Alignment.center,
            child: showFront
                ? _FinanceFront(
                    income: income,
                    expenses: expenses,
                    progress: savingsProgress.clamp(0.0, 1.0),
                  )
                : Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _FinanceBack(entries: widget.entries),
                  ),
          );
        },
      ),
    );
  }
}

class _FinanceFront extends StatelessWidget {
  final double income;
  final double expenses;
  final double progress;

  const _FinanceFront({
    required this.income,
    required this.expenses,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      gradient: RodMaeColors.sapphireGradient,
      borderColor: RodMaeColors.sky.withValues(alpha: 0.22),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: 'SHARED DEPOSITS',
                  value: Formatters.compactMoney(income),
                  color: RodMaeColors.mint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricBox(
                  label: 'TOTAL EXPENSES',
                  value: Formatters.compactMoney(expenses),
                  color: RodMaeColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      color: RodMaeColors.electricBlue,
                    ),
                    Center(
                      child: Text(
                        '${(progress * 100).round()}%',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spouse Target Savings',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      income > 0 
                          ? 'Tap this card to flip into allocation details.'
                          : 'No entries. Add income to view savings progress!',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinanceBack extends StatelessWidget {
  final List<FinanceEntry> entries;

  const _FinanceBack({required this.entries});

  @override
  Widget build(BuildContext context) {
    final categories = <String, double>{};
    for (final entry in entries.where((entry) => entry.type == FinanceType.expense)) {
      categories[entry.category] = (categories[entry.category] ?? 0) + entry.amount;
    }
    final rows = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return GlassCard(
      gradient: const LinearGradient(
        colors: [Color(0xFF111827), Color(0xFF0A192F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.all(18),
      borderColor: RodMaeColors.gold.withValues(alpha: 0.2),
      child: SizedBox(
        height: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expense Allocation',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                children: rows.take(3).map((row) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.key,
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          Formatters.compactMoney(row.value),
                          style: GoogleFonts.robotoMono(
                            color: RodMaeColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            Text(
              'Tap again to return to target savings card.',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.robotoMono(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceEntryForm extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController amountController;
  final TextEditingController categoryController;
  final FinanceType type;
  final bool saving;
  final ValueChanged<FinanceType> onTypeChanged;
  final VoidCallback onSubmit;

  const _FinanceEntryForm({
    required this.titleController,
    required this.amountController,
    required this.categoryController,
    required this.type,
    required this.saving,
    required this.onTypeChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      color: Colors.black.withValues(alpha: isDark ? 0.23 : 0.03),
      borderColor: Colors.white.withValues(alpha: isDark ? 0.06 : 0.3),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Title, e.g. Electricity',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Amount PHP',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: categoryController,
            decoration: const InputDecoration(
              hintText: 'Category',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TypeChip(
                label: 'Expense',
                selected: type == FinanceType.expense,
                color: RodMaeColors.coral,
                onTap: () => onTypeChanged(FinanceType.expense),
              ),
              const SizedBox(width: 8),
              _TypeChip(
                label: 'Income',
                selected: type == FinanceType.income,
                color: RodMaeColors.mint,
                onTap: () => onTypeChanged(FinanceType.income),
              ),
              const Spacer(),
              PrimaryPillButton(
                label: 'Add',
                icon: Icons.add_rounded,
                busy: saving,
                onPressed: onSubmit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white.withValues(alpha: isDark ? 0.05 : 0.6),
          borderRadius: BorderRadius.circular(15),
          border: selected ? null : Border.all(color: Colors.black.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? Colors.white : (isDark ? Colors.white : RodMaeColors.lightTextSoft),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class FinanceLedgerTile extends StatelessWidget {
  final FinanceEntry entry;

  const FinanceLedgerTile(this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    final income = entry.type == FinanceType.income;
    final color = income ? RodMaeColors.mint : RodMaeColors.gold;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.3),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              income ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      entry.category,
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Formatters.date(entry.date),
                      style: GoogleFonts.inter(
                        color: isDark ? Colors.white30 : Colors.black26,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${income ? '+' : '-'} ${Formatters.compactMoney(entry.amount)}',
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
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
    try {
      final plan = await GeminiCompanionService.instance.generateMealPlan(prompt);
      setState(() {
        _plan.clear();
        _plan.addAll(plan);
        _groceryItems.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI meal grid generated.')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
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
