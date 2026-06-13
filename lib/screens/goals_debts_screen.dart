import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/savings_goal.dart';
import '../models/debt.dart';
import '../models/wallet.dart';
import '../services/finance_repository.dart';
import '../services/auth_service.dart';
import '../core/constants.dart';

class GoalsDebtsScreen extends StatefulWidget {
  const GoalsDebtsScreen({super.key});

  @override
  State<GoalsDebtsScreen> createState() => _GoalsDebtsScreenState();
}

class _GoalsDebtsScreenState extends State<GoalsDebtsScreen> with SingleTickerProviderStateMixin {
  List<Wallet> _wallets = [];
  bool _loadingWallets = true;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  Future<void> _loadWallets() async {
    try {
      final list = await FinanceRepository.instance.fetchWallets();
      setState(() {
        _wallets = list;
        _loadingWallets = false;
      });
    } catch (_) {
      setState(() => _loadingWallets = false);
    }
  }

  void _showAddGoalDialog() {
    final titleController = TextEditingController();
    final targetController = TextEditingController();
    final savedController = TextEditingController();
    DateTime? selectedDeadline;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                backgroundColor: isDark ? RodMaeColors.background.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                title: Text(
                  '🎯 NEW SAVINGS GOAL',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : RodMaeColors.navy),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black),
                        decoration: const InputDecoration(
                          labelText: 'Goal Title',
                          hintText: 'e.g. Wedding Ring, Honeymoon',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: targetController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black),
                        decoration: const InputDecoration(
                          labelText: 'Target Amount (PHP)',
                          hintText: '0.00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: savedController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black),
                        decoration: const InputDecoration(
                          labelText: 'Initial Saved Amount (PHP)',
                          hintText: '0.00',
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Deadline Picker
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (date != null) {
                            setDialogState(() => selectedDeadline = date);
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                selectedDeadline == null
                                    ? 'Set Deadline (Optional)'
                                    : 'Deadline: ${Formatters.date(selectedDeadline!)}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: selectedDeadline == null ? RodMaeColors.textMuted : (isDark ? Colors.white : Colors.black),
                                ),
                              ),
                              const Icon(Icons.calendar_month_rounded, size: 18, color: RodMaeColors.gold),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('CANCEL', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: RodMaeColors.textMuted)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final title = titleController.text.trim();
                      final target = double.tryParse(targetController.text) ?? 0.0;
                      final saved = double.tryParse(savedController.text) ?? 0.0;

                      if (title.isEmpty || target <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid title and target amount.')),
                        );
                        return;
                      }

                      final goal = SavingsGoal(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        householdId: AppConfig.coupleId,
                        name: title,
                        targetAmount: target,
                        currentAmount: saved,
                        category: 'life_event',
                        targetDate: selectedDeadline,
                        createdAt: DateTime.now(),
                      );

                      await FinanceRepository.instance.insertSavingsGoal(goal);
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Savings goal created successfully!')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: RodMaeColors.gold),
                    child: Text('CREATE', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: RodMaeColors.navy)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSettleDebtDialog(Debt debt) {
    if (_loadingWallets) return;
    if (_wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a wallet first in Supabase to settle payments.')),
      );
      return;
    }

    final amountController = TextEditingController(text: debt.remainingAmount.toStringAsFixed(2));
    Wallet selectedWallet = _wallets.first;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AlertDialog(
                backgroundColor: isDark ? RodMaeColors.background.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                ),
                title: Text(
                  '🤝 SETTLE SPLIT DEBT',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16, color: isDark ? Colors.white : RodMaeColors.navy),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      debt.title,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      decoration: const InputDecoration(
                        labelText: 'Payment Amount (PHP)',
                        hintText: '0.00',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Wallet>(
                      value: selectedWallet,
                      style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                      dropdownColor: isDark ? RodMaeColors.background : Colors.white,
                      decoration: const InputDecoration(
                        labelText: 'Select Source Wallet',
                      ),
                      items: _wallets.map((wallet) {
                        return DropdownMenuItem(
                          value: wallet,
                          child: Text('${wallet.name} (₱${wallet.balance.toStringAsFixed(0)})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedWallet = val);
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('CANCEL', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: RodMaeColors.textMuted)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final amt = double.tryParse(amountController.text) ?? 0.0;
                      if (amt <= 0 || amt > debt.remainingAmount) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid amount (up to remaining debt).')),
                        );
                        return;
                      }

                      Navigator.pop(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await FinanceRepository.instance.recordDebtPayment(debt.id, amt, selectedWallet.id);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Payment recorded. Debt updated successfully!')),
                        );
                        // Refresh wallets
                        _loadWallets();
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Payment failed: $e')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: RodMaeColors.gold),
                    child: Text('CONFIRM SETTLE', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: RodMaeColors.navy)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: RodMaeColors.getAppBackground(isDark),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Premium glassmorphic app bar & tab bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'GOALS & DEBTS',
                        style: GoogleFonts.playfairDisplay(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: RodMaeColors.gold,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      labelColor: RodMaeColors.navy,
                      unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
                      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8),
                      tabs: const [
                        Tab(text: '🎯 SAVINGS GOALS'),
                        Tab(text: '🤝 SPLIT DEBTS'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Tab contents
                Expanded(
                  child: TabBarView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildSavingsGoalsTab(),
                      _buildDebtsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavingsGoalsTab() {
    return StreamBuilder<List<SavingsGoal>>(
      stream: FinanceRepository.instance.watchSavingsGoals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: RodMaeColors.gold));
        }

        final goals = snapshot.data ?? [];

        return Stack(
          children: [
            if (goals.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.track_changes_rounded, size: 64, color: RodMaeColors.gold),
                      const SizedBox(height: 16),
                      Text(
                        'No savings goals created yet.',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create shared targets like wedding expenses, house downpayment, or honeymoon travel!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: RodMaeColors.textSoft, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                itemCount: goals.length,
                itemBuilder: (context, index) {
                  final goal = goals[index];
                  final double progress = goal.targetAmount == 0 ? 0.0 : (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0);
                  final percent = (progress * 100).toStringAsFixed(0);

                  return GlassBox(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Thick circular progress indicator with percentage inside
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 68,
                              height: 68,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 7,
                                color: RodMaeColors.gold,
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            Text(
                              '$percent%',
                              style: GoogleFonts.robotoMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: RodMaeColors.gold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.title.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    'Saved: ',
                                    style: GoogleFonts.inter(fontSize: 11, color: RodMaeColors.textMuted),
                                  ),
                                  Text(
                                    '₱${Formatters.compactMoney(goal.savedAmount).replaceAll('PHP ', '')}',
                                    style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: RodMaeColors.mint),
                                  ),
                                  Text(
                                    ' / ₱${Formatters.compactMoney(goal.targetAmount).replaceAll('PHP ', '')}',
                                    style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                                  ),
                                ],
                              ),
                              if (goal.deadline != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_filled_rounded, size: 12, color: RodMaeColors.coral),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Target Date: ${Formatters.date(goal.deadline!)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: RodMaeColors.coral,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: _showAddGoalDialog,
                backgroundColor: RodMaeColors.gold,
                foregroundColor: RodMaeColors.navy,
                icon: const Icon(Icons.add_rounded),
                label: Text('NEW GOAL', style: GoogleFonts.inter(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDebtsTab() {
    return StreamBuilder<List<Debt>>(
      stream: FinanceRepository.instance.watchDebts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: RodMaeColors.gold));
        }

        final debts = snapshot.data ?? [];

        // Determine logged-in partner orientation
        final activePartner = PartnerIdentity.active.value.label.toLowerCase();
        final isRodel = activePartner == 'rodel';

        // Categorize debts dynamically based on logged in user:
        // DebtType.owe means Eurine owes Rodel.
        // DebtType.owed means Rodel owes Eurine.
        final owedToUs = debts.where((d) {
          if (d.isFullyPaid) return false;
          return isRodel ? d.type == DebtType.owe : d.type == DebtType.owed;
        }).toList();

        final weOwe = debts.where((d) {
          if (d.isFullyPaid) return false;
          return isRodel ? d.type == DebtType.owed : d.type == DebtType.owe;
        }).toList();

        if (debts.isEmpty || (owedToUs.isEmpty && weOwe.isEmpty)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.handshake_rounded, size: 64, color: RodMaeColors.gold),
                  const SizedBox(height: 16),
                  Text(
                    'No active debts logged.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable "Split this Bill" when adding transactions to automatically track split debts here!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: RodMaeColors.textSoft, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (owedToUs.isNotEmpty) ...[
              _buildSectionHeader('🤝 OWED TO YOU (COLLECT FUNDS)'),
              const SizedBox(height: 8),
              ...owedToUs.map((d) => _buildDebtCard(d, isOwedToUs: true)),
              const SizedBox(height: 20),
            ],
            if (weOwe.isNotEmpty) ...[
              _buildSectionHeader('💸 YOU OWE (PAY DOWN DEBTS)'),
              const SizedBox(height: 8),
              ...weOwe.map((d) => _buildDebtCard(d, isOwedToUs: false)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: RodMaeColors.gold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDebtCard(Debt debt, {required bool isOwedToUs}) {
    final themeColor = isOwedToUs ? RodMaeColors.mint : RodMaeColors.coral;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassBox(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOwedToUs ? Icons.call_received_rounded : Icons.call_made_rounded,
                  color: themeColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt.title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOwedToUs ? 'Partner owes you' : 'You owe partner',
                      style: GoogleFonts.inter(fontSize: 10, color: RodMaeColors.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₱${Formatters.compactMoney(debt.remainingAmount).replaceAll('PHP ', '')}',
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: themeColor,
                    ),
                  ),
                  Text(
                    'of ₱${Formatters.compactMoney(debt.totalAmount).replaceAll('PHP ', '')}',
                    style: GoogleFonts.inter(fontSize: 9, color: RodMaeColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showSettleDebtDialog(debt),
                icon: const Icon(Icons.payment_rounded, size: 14),
                label: Text(
                  isOwedToUs ? 'MARK AS PAID' : 'SETTLE PAYMENT',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor.withValues(alpha: 0.12),
                  foregroundColor: themeColor,
                  elevation: 0,
                  side: BorderSide(color: themeColor.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GlassBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const GlassBox({
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassColor = isDark 
        ? Colors.white.withValues(alpha: 0.04) 
        : Colors.black.withValues(alpha: 0.02);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
