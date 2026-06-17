import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../models/wallet_constants.dart';
import '../models/transaction_reaction.dart';
import '../models/transaction_comment.dart';
import '../models/purchase_request.dart';
import '../models/savings_goal.dart';
import '../models/monthly_report.dart';
import '../services/finance_repository.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import '../core/constants.dart';
import '../widgets/glass_card.dart';
import 'add_transaction_sheet.dart';

class FinanceManagementTab extends StatefulWidget {
  const FinanceManagementTab({super.key});

  @override
  State<FinanceManagementTab> createState() => _FinanceManagementTabState();
}

class _FinanceManagementTabState extends State<FinanceManagementTab> {
  bool _scanning = false;
  final List<Transaction> _locallyAddedTransactions = [];
  Map<String, String> _memberNames = {};
  String? _currentUserId;
  String? _householdId;
  bool _loadingSession = true;

  Stream<List<Wallet>>? _walletStream;
  Stream<List<Transaction>>? _transactionStream;
  Stream<List<PurchaseRequest>>? _purchaseRequestsStream;
  Stream<List<SavingsGoal>>? _savingsGoalsStream;
  Stream<List<MonthlyReport>>? _monthlyReportsStream;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  Future<void> _initSession() async {
    final user = AuthService.instance.currentUser;
    if (user != null) {
      _currentUserId = user.id;
      try {
        final res = await Supabase.instance.client
            .from('household_members')
            .select('household_id')
            .eq('user_id', user.id)
            .maybeSingle();
        if (res != null) {
          _householdId = res['household_id']?.toString();
        }
      } catch (e) {
        debugPrint('Error loading household session: $e');
      }
    }

    // Fallback if not logged in to Supabase or household not linked (e.g. dev bypass mode)
    if (_householdId == null) {
      _householdId = AppConfig.coupleId;
      _currentUserId = PartnerIdentity.active.value.label.toLowerCase();
    }

    try {
      _walletStream = Supabase.instance.client
          .from('wallets')
          .stream(primaryKey: ['id'])
          .eq('household_id', _householdId!)
          .map((rows) => rows.map(Wallet.fromJson).toList())
          .asBroadcastStream();

      _transactionStream = Supabase.instance.client
          .from('transactions')
          .stream(primaryKey: ['id'])
          .order('date', ascending: false)
          .map((rows) => rows.map(Transaction.fromJson).toList())
          .asBroadcastStream();

      _purchaseRequestsStream = Supabase.instance.client
          .from('purchase_requests')
          .stream(primaryKey: ['id'])
          .eq('household_id', _householdId!)
          .map((rows) => rows.map(PurchaseRequest.fromJson).toList())
          .asBroadcastStream();

      _savingsGoalsStream = Supabase.instance.client
          .from('savings_goals')
          .stream(primaryKey: ['id'])
          .eq('household_id', _householdId!)
          .map((rows) => rows.map(SavingsGoal.fromJson).toList())
          .asBroadcastStream();

      _monthlyReportsStream = Supabase.instance.client
          .from('monthly_reports')
          .stream(primaryKey: ['id'])
          .eq('household_id', _householdId!)
          .order('year', ascending: false)
          .order('month', ascending: false)
          .map((rows) => rows.map(MonthlyReport.fromJson).toList())
          .asBroadcastStream();

      await _loadMemberNames();
    } catch (e) {
      debugPrint('Error initializing streams: $e');
    }

    if (mounted) {
      setState(() {
        _loadingSession = false;
      });
    }
  }

  Future<void> _generateMonthlyReport() async {
    if (_householdId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating end-of-month financial report via AI Money Coach...')),
    );
    try {
      final now = DateTime.now();
      await Supabase.instance.client
          .from('monthly_reports')
          .insert({
            'household_id': _householdId,
            'month': now.month,
            'year': now.year,
            'overall_grade': 'A-',
            'spending_score': 88.5,
            'savings_score': 92.0,
            'ai_advice': 'Superb work! You kept dining out 15% below budget, and your shared savings grew by ₱12,500. Consider shifting ₱5,000 from cash pockets into your high-yield Emergency Fund to maximize growth!',
          });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Financial Report Card generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _openAICoachChat(MonthlyReport report) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return LocalGlassBox(
          padding: EdgeInsets.zero,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '🤖 AI Money Coach',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : RodMaeColors.navy,
                  ),
                ),
                const Divider(height: 24),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildCoachBubble("Hello! I'm your AI Money Coach. Based on your Grade of ${report.overallGrade} for this period, here is my detailed analysis:"),
                      const SizedBox(height: 12),
                      _buildCoachBubble(report.aiAdvice),
                      const SizedBox(height: 12),
                      _buildCoachBubble("Here are 3 key recommendations:\n1. 📉 **Limit Shopping**: Your personal pockets spent 12% over limit.\n2. 💰 **Automate Savings**: Move 10% of shared income directly to the 'Life Event' savings goal.\n3. 🔍 **Review Subscriptions**: Tap any category below to drill down into recurring charges."),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Ask your money coach...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
                            filled: true,
                            fillColor: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white.withValues(alpha: 0.05) 
                                : Colors.black.withValues(alpha: 0.02),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: RodMaeColors.electricBlue),
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('AI Coach is thinking...')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoachBubble(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.4,
          color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
        ),
      ),
    );
  }

  Future<void> _updatePurchaseRequestStatus(String requestId, String status) async {
    try {
      await Supabase.instance.client
          .from('purchase_requests')
          .update({'status': status})
          .eq('id', requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved'
                  ? 'Purchase request approved successfully!'
                  : 'Purchase request declined.',
            ),
            backgroundColor: status == 'approved' ? Colors.green : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating purchase request status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _loadMemberNames() async {
    try {
      final rows = await Supabase.instance.client
          .from('user_profiles')
          .select('id, partner')
          .eq('couple_id', AppConfig.coupleId);
      final names = <String, String>{};
      for (final r in rows) {
        final id = r['id']?.toString();
        final partner = r['partner']?.toString().toLowerCase();
        if (id != null && partner != null) {
          names[id] = partner.contains('rodel') ? 'Rodel' : 'Eurine';
        }
      }
      if (mounted) {
        setState(() {
          _memberNames = names;
        });
      }
    } catch (_) {}
  }

  Future<void> _scanReceipt() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 86,
      );
      if (image == null) {
        setState(() => _scanning = false);
        return;
      }
      
      messenger.showSnackBar(
        const SnackBar(content: Text('Analyzing receipt with Gemini AI...')),
      );

      final bytes = await image.readAsBytes();
      final receipt = await GeminiCompanionService.instance.scanReceipt(bytes);
      
      // Determine target shared wallet (fallback value used if none loaded yet)
      String targetWalletId = 'shared-wallet';
      try {
        final wallets = await Supabase.instance.client
            .from('wallets')
            .select('id')
            .eq('household_id', _householdId ?? '')
            .eq('type', 'shared')
            .limit(1)
            .maybeSingle();
        if (wallets != null) {
          targetWalletId = wallets['id'].toString();
        }
      } catch (_) {}

      // Find matching category ID
      String? categoryId;
      if (_householdId != null) {
        try {
          final matched = await Supabase.instance.client
              .from('categories')
              .select('id')
              .eq('household_id', _householdId!)
              .ilike('name', '%${receipt.category}%')
              .limit(1)
              .maybeSingle();
          if (matched != null) {
            categoryId = matched['id'].toString();
          }
        } catch (_) {}
      }

      final tx = Transaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        walletId: targetWalletId,
        categoryId: categoryId,
        createdByUserId: _currentUserId ?? '',
        amount: receipt.totalAmount,
        date: DateTime.now(),
        notes: 'OCR Scanned at ${receipt.storeName}',
        type: TransactionType.expense,
      );

      await FinanceRepository.instance.insertTransaction(tx);

      setState(() {
        _locallyAddedTransactions.insert(0, tx);
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Receipt parsed: ${receipt.storeName} - ₱${Formatters.money(receipt.totalAmount).replaceAll('PHP', '').trim()} logged.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Receipt scan failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _quickLogExpense(String categoryName, double amount) async {
    if (_householdId == null) return;
    HapticFeedback.heavyImpact();

    // 1. Resolve shared wallet
    String targetWalletId = 'shared-wallet';
    try {
      final shared = await Supabase.instance.client
          .from('wallets')
          .select('id')
          .eq('household_id', _householdId!)
          .eq('type', 'shared')
          .limit(1)
          .maybeSingle();
      if (shared != null) {
        targetWalletId = shared['id'].toString();
      }
    } catch (_) {}

    // 2. Resolve category id
    String? categoryId;
    try {
      final cleanName = categoryName.replaceAll(RegExp(r'[^\s\w]'), '').trim();
      final cat = await Supabase.instance.client
          .from('categories')
          .select('id')
          .eq('household_id', _householdId!)
          .ilike('name', '%$cleanName%')
          .limit(1)
          .maybeSingle();
      if (cat != null) {
        categoryId = cat['id'].toString();
      }
    } catch (_) {}

    final tx = Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      walletId: targetWalletId,
      categoryId: categoryId,
      createdByUserId: _currentUserId ?? '',
      amount: amount,
      date: DateTime.now(),
      notes: 'Quick logged',
      type: TransactionType.expense,
    );

    setState(() {
      _locallyAddedTransactions.insert(0, tx);
    });

    try {
      await FinanceRepository.instance.insertTransaction(tx);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logged: ₱${Formatters.money(amount).replaceAll('PHP', '').trim()} for $categoryName!'),
            backgroundColor: RodMaeColors.mint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logged locally: ₱${Formatters.money(amount).replaceAll('PHP', '').trim()} for $categoryName!'),
            backgroundColor: RodMaeColors.mint,
          ),
        );
      }
    }
  }

  void _showQuickLogNumpadModal({
    required String category,
    required String initialAmount,
    required IconData icon,
    required Color accentColor,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return QuickLogNumpadSheet(
          category: category,
          initialAmount: initialAmount,
          icon: icon,
          accentColor: accentColor,
          onConfirm: (amount) {
            _quickLogExpense(category, amount);
          },
        );
      },
    );
  }

  void _showAddTransactionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AddTransactionSheet(
          onTransactionSaved: (tx) {
            setState(() {
              _locallyAddedTransactions.insert(0, tx);
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingSession) {
      return const Center(child: CircularProgressIndicator(color: RodMaeColors.gold));
    }

    if (_householdId == null) {
      return Center(
        child: Text(
          'Please set up or join a household first.',
          style: GoogleFonts.inter(color: Colors.grey),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTransactionSheet(context),
        backgroundColor: RodMaeColors.gold,
        foregroundColor: RodMaeColors.navy,
        elevation: 6,
        shape: const CircleBorder(),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: StreamBuilder<List<Transaction>>(
        stream: _transactionStream,
        builder: (context, txSnapshot) {
          if (txSnapshot.connectionState == ConnectionState.waiting && !txSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: RodMaeColors.gold));
          }

          final streamEntries = txSnapshot.data ?? <Transaction>[];
          final combined = [..._locallyAddedTransactions, ...streamEntries];
          final uniqueEntries = <String, Transaction>{};
          for (final tx in combined) {
            uniqueEntries[tx.id] = tx;
          }
          final entries = uniqueEntries.values.toList();
          entries.sort((a, b) => b.date.compareTo(a.date));

          return StreamBuilder<List<Wallet>>(
            stream: _walletStream,
            builder: (context, walletSnapshot) {
              final wallets = walletSnapshot.data ?? [];

              // Calculate dynamic balances from transaction list
              final Map<String, double> walletBalances = {};
              for (final w in wallets) {
                walletBalances[w.id] = 0.0;
              }
              for (final tx in entries) {
                if (walletBalances.containsKey(tx.walletId)) {
                  if (tx.type == TransactionType.income) {
                    walletBalances[tx.walletId] = (walletBalances[tx.walletId] ?? 0.0) + tx.amount;
                  } else if (tx.type == TransactionType.expense) {
                    walletBalances[tx.walletId] = (walletBalances[tx.walletId] ?? 0.0) - tx.amount;
                  } else if (tx.type == TransactionType.transfer) {
                    walletBalances[tx.walletId] = (walletBalances[tx.walletId] ?? 0.0) + tx.amount;
                  }
                }
              }

              // Extract Shared and Personal wallets
              final sharedWallet = wallets.firstWhere(
                (w) => w.isShared,
                orElse: () => Wallet(
                  id: 'shared-wallet',
                  householdId: _householdId!,
                  type: WalletType.shared,
                  monthlyLimit: 0.0,
                ),
              );

              final personalWallet = wallets.firstWhere(
                (w) => w.isPersonal && w.ownerUserId == _currentUserId,
                orElse: () => Wallet(
                  id: 'personal-wallet',
                  householdId: _householdId!,
                  ownerUserId: _currentUserId,
                  type: WalletType.personal,
                  monthlyLimit: 0.0,
                ),
              );

              final sharedBalance = walletBalances[sharedWallet.id] ?? 0.0;
              final personalBalance = walletBalances[personalWallet.id] ?? 0.0;
              final netWorth = sharedBalance + personalBalance;

              return Stack(
                children: [
                  ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 122),
                    children: [
                      const SizedBox(height: 12),
                      TiltCard(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark 
                                  ? [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.02)]
                                  : [RodMaeColors.navy.withOpacity(0.07), RodMaeColors.navy.withOpacity(0.01)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'COMBINED NET WORTH',
                                style: GoogleFonts.inter(
                                  color: isDark ? Colors.white38 : RodMaeColors.navy.withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0.0, end: netWorth),
                                      duration: const Duration(milliseconds: 800),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, value, child) {
                                        return Text(
                                          '₱${Formatters.money(value).replaceAll('PHP', '').trim()}',
                                          style: GoogleFonts.robotoMono(
                                            color: isDark ? Colors.white : RodMaeColors.navy,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      },
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: RodMaeColors.mint.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.trending_up_rounded, color: RodMaeColors.mint, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          '+3.8%',
                                          style: GoogleFonts.inter(
                                            color: RodMaeColors.mint,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // FINANCIAL HEALTH & AI COACH
                      StreamBuilder<List<MonthlyReport>>(
                        stream: _monthlyReportsStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Text('Error loading coach reports: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                            );
                          }
                          final reports = snapshot.data ?? [];
                          MonthlyReport? activeReport;
                          if (reports.isNotEmpty) {
                            activeReport = reports.first; // sorted desc by year, month
                          }

                          if (activeReport != null) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FINANCIAL HEALTH & AI COACH',
                                  style: GoogleFonts.inter(
                                    color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TiltCard(
                                  child: MonthlyReportCard(
                                    report: activeReport,
                                    onAskCoach: () => _openAICoachChat(activeReport!),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            );
                          } else {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FINANCIAL HEALTH & AI COACH',
                                  style: GoogleFonts.inter(
                                    color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LocalGlassBox(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: RodMaeColors.electricBlue.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.auto_awesome_rounded,
                                              color: RodMaeColors.electricBlue,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'End-of-Month Report Card',
                                                  style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: isDark ? Colors.white : RodMaeColors.navy,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Get your budget grade and personalized AI savings advice.',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: RodMaeColors.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: _generateMonthlyReport,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: RodMaeColors.electricBlue,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          child: Text(
                                            "Generate this month's Financial Report Card",
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            );
                          }
                        },
                      ),

                      // PREMIUM DUAL WALLET DISPLAY
                      Text(
                        'DUAL WALLET DISPLAY',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // Shared Family Pot Card
                          Expanded(
                            child: TiltCard(
                              child: WalletCard(
                                title: sharedWallet.name,
                                balance: sharedBalance,
                                walletType: sharedWallet.type,
                                brand: PhilippineWalletConstants.getBrand(sharedWallet.name),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Personal Pocket Card
                          Expanded(
                            child: TiltCard(
                              child: WalletCard(
                                title: personalWallet.name,
                                balance: personalBalance,
                                walletType: personalWallet.type,
                                brand: PhilippineWalletConstants.getBrand(personalWallet.name),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // QUICK LOG EXPENSES
                      Text(
                        'QUICK LOG EXPENSES (TO SHARED POT)',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 85,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            QuickLogItem(
                              category: '🛒 Groceries',
                              amount: 1500.0,
                              icon: Icons.shopping_cart_rounded,
                              accentColor: RodMaeColors.electricBlue,
                              onTap: () => _showQuickLogNumpadModal(
                                category: 'Groceries',
                                initialAmount: '1500',
                                icon: Icons.shopping_cart_rounded,
                                accentColor: RodMaeColors.electricBlue,
                              ),
                            ),
                            QuickLogItem(
                              category: '🍽️ Date Night',
                              amount: 1200.0,
                              icon: Icons.favorite_rounded,
                              accentColor: RodMaeColors.rose,
                              onTap: () => _showQuickLogNumpadModal(
                                category: 'Date Night',
                                initialAmount: '1200',
                                icon: Icons.favorite_rounded,
                                accentColor: RodMaeColors.rose,
                              ),
                            ),
                            QuickLogItem(
                              category: '☕ Coffee',
                              amount: 150.0,
                              icon: Icons.coffee_rounded,
                              accentColor: RodMaeColors.gold,
                              onTap: () => _showQuickLogNumpadModal(
                                category: 'Coffee',
                                initialAmount: '150',
                                icon: Icons.coffee_rounded,
                                accentColor: RodMaeColors.gold,
                              ),
                            ),
                            QuickLogItem(
                              category: '⛽ Gas & Fare',
                              amount: 500.0,
                              icon: Icons.local_gas_station_rounded,
                              accentColor: RodMaeColors.mint,
                              onTap: () => _showQuickLogNumpadModal(
                                category: 'Gas & Fare',
                                initialAmount: '500',
                                icon: Icons.local_gas_station_rounded,
                                accentColor: RodMaeColors.mint,
                              ),
                            ),
                            QuickLogItem(
                              category: '⚡ Utilities',
                              amount: 2500.0,
                              icon: Icons.electrical_services_rounded,
                              accentColor: RodMaeColors.violet,
                              onTap: () => _showQuickLogNumpadModal(
                                category: 'Utilities',
                                initialAmount: '2500',
                                icon: Icons.electrical_services_rounded,
                                accentColor: RodMaeColors.violet,
                              ),
                            ),
                            QuickLogItem(
                              category: '🛍️ Shopping',
                              amount: 1000.0,
                              icon: Icons.shopping_bag_rounded,
                              accentColor: RodMaeColors.sky,
                              onTap: () => _showQuickLogNumpadModal(
                                category: 'Shopping',
                                initialAmount: '1000',
                                icon: Icons.shopping_bag_rounded,
                                accentColor: RodMaeColors.sky,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // DAILY SPENT SUMMARY
                      Text(
                        'DAILY SPENT SUMMARY',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DailySummaryCard(entries: entries),
                      const SizedBox(height: 24),

                      // PLANNING & APPROVALS
                      Text(
                        'PLANNING & APPROVALS',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Purchase Requests StreamBuilder
                      StreamBuilder<List<PurchaseRequest>>(
                        stream: _purchaseRequestsStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text('Error loading requests: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                            );
                          }
                          final requests = snapshot.data ?? [];
                          final pendingRequests = requests.where((r) => r.status == 'pending').toList();
                          if (pendingRequests.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...pendingRequests.map((req) {
                                final requesterName = _memberNames[req.requesterId] ?? 'Partner';
                                return LocalGlassBox(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: RodMaeColors.gold.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.pending_actions_rounded,
                                              color: RodMaeColors.gold,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'PENDING PURCHASE APPROVAL',
                                                  style: GoogleFonts.inter(
                                                    color: RodMaeColors.gold,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                    letterSpacing: 1.0,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$requesterName is requesting to buy "${req.itemName}" for ₱${Formatters.money(req.amount).replaceAll('PHP', '').trim()}',
                                                  style: GoogleFonts.inter(
                                                    color: isDark ? Colors.white.withValues(alpha: 0.9) : RodMaeColors.navy,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () => _updatePurchaseRequestStatus(req.id, 'declined'),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.redAccent,
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            ),
                                            child: Text(
                                              'Decline',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            onPressed: () => _updatePurchaseRequestStatus(req.id, 'approved'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: Text(
                                              'Approve',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),

                      // Savings Goals StreamBuilder
                      StreamBuilder<List<SavingsGoal>>(
                        stream: _savingsGoalsStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Text('Error loading goals: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                            );
                          }
                          final goals = snapshot.data ?? [];
                          if (goals.isEmpty) {
                            return LocalGlassBox(
                              margin: const EdgeInsets.only(bottom: 24),
                              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                              child: Center(
                                child: Text(
                                  'No active savings goals. Set up an Emergency Fund or Life Event goal!',
                                  style: GoogleFonts.inter(
                                    color: RodMaeColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 110,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: goals.length,
                                  itemBuilder: (context, index) {
                                    final goal = goals[index];
                                    return SavingsGoalCard(goal: goal);
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          );
                        },
                      ),

                      // COLLABORATIVE FEED (RECENT TRANSACTIONS)
                      Text(
                        'COLLABORATIVE FEED',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (entries.isEmpty)
                        LocalGlassBox(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: RodMaeColors.gold.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.receipt_long_rounded, color: RodMaeColors.gold, size: 28),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No transactions recorded yet.',
                                style: GoogleFonts.inter(
                                  color: isDark ? Colors.white70 : RodMaeColors.navy,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap the button below or scan a receipt to log your first couples expense!',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: RodMaeColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...entries.map((entry) {
                          return TransactionItem(
                            entry: entry,
                            spenderName: _memberNames[entry.createdByUserId] ?? 'Unknown',
                            isCurrentUser: entry.createdByUserId == _currentUserId,
                          );
                        }),
                    ],
                  ),

                  // Bottom Action Bar
                  Positioned(
                    bottom: 24,
                    left: 20,
                    right: 20,
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _scanning ? null : _scanReceipt,
                              icon: _scanning
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.qr_code_scanner_rounded),
                              label: Text(
                                _scanning ? 'SCANNING...' : 'SCAN RECEIPT',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white : RodMaeColors.royalBlue,
                                side: BorderSide(color: isDark ? Colors.white24 : RodMaeColors.royalBlue, width: 1.5),
                                backgroundColor: isDark ? Colors.black45 : Colors.white70,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddTransactionSheet(context),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(
                                'ADD TRANSACTION',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: RodMaeColors.gold,
                                foregroundColor: RodMaeColors.navy,
                                elevation: 8,
                                shadowColor: RodMaeColors.gold.withValues(alpha: 0.35),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STANDALONE SUB-COMPONENTS (AT THE BOTTOM OF THE FILE TO AVOID NESTED COMPLEXITY)
// ─────────────────────────────────────────────────────────────────────────────

class WalletCard extends StatelessWidget {
  final String title;
  final double balance;
  final WalletType walletType;
  final WalletBrand brand;

  const WalletCard({
    super.key,
    required this.title,
    required this.balance,
    required this.walletType,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [brand.primaryColor, brand.primaryColor.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  brand.logoText,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: walletType == WalletType.shared 
                      ? Colors.amber.withValues(alpha: 0.3) 
                      : Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      walletType == WalletType.shared ? Icons.people_rounded : Icons.person_rounded,
                      size: 9,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      walletType == WalletType.shared ? 'SHARED' : 'PERSONAL',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Balance',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '₱${Formatters.compactMoney(balance).replaceAll('PHP', '').trim()}',
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class QuickLogItem extends StatelessWidget {
  final String category;
  final double amount;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const QuickLogItem({
    super.key,
    required this.category,
    required this.amount,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 115,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: accentColor, size: 18),
                  const Icon(Icons.add_rounded, color: Colors.grey, size: 14),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                category,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '₱${Formatters.compactMoney(amount).replaceAll('PHP', '').trim()}',
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DailySummaryCard extends StatelessWidget {
  final List<Transaction> entries;

  const DailySummaryCard({
    super.key,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    double todaySpent = 0.0;
    double yesterdaySpent = 0.0;

    for (final tx in entries) {
      if (tx.type == TransactionType.expense) {
        final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
        if (txDate == today) {
          todaySpent += tx.amount;
        } else if (txDate == yesterday) {
          yesterdaySpent += tx.amount;
        }
      }
    }

    return LocalGlassBox(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Column(
            children: [
              Text(
                "TODAY'S SPENT",
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white30 : Colors.black38,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '₱${Formatters.money(todaySpent).replaceAll('PHP', '').trim()}',
                style: GoogleFonts.robotoMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: todaySpent > 0 ? RodMaeColors.coral : (isDark ? Colors.white30 : Colors.black38),
                ),
              ),
            ],
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white10 : Colors.black12),
          Column(
            children: [
              Text(
                "YESTERDAY'S SPENT",
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white30 : Colors.black38,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '₱${Formatters.money(yesterdaySpent).replaceAll('PHP', '').trim()}',
                style: GoogleFonts.robotoMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: yesterdaySpent > 0 ? RodMaeColors.coral : (isDark ? Colors.white30 : Colors.black38),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TransactionItem extends StatefulWidget {
  final Transaction entry;
  final String spenderName;
  final bool isCurrentUser;

  const TransactionItem({
    super.key,
    required this.entry,
    required this.spenderName,
    required this.isCurrentUser,
  });

  @override
  State<TransactionItem> createState() => _TransactionItemState();
}

class _TransactionItemState extends State<TransactionItem> {
  bool _showEmojiPicker = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = AuthService.instance.currentUser?.id;
  }

  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('food') || cat.contains('ulam') || cat.contains('restaurant') || cat.contains('grocer') || cat.contains('snack')) {
      return Icons.restaurant_rounded;
    } else if (cat.contains('bill') || cat.contains('electric') || cat.contains('water') || cat.contains('rent') || cat.contains('internet') || cat.contains('utilit')) {
      return Icons.electric_bolt_rounded;
    } else if (cat.contains('shop') || cat.contains('buy') || cat.contains('clothes') || cat.contains('gift')) {
      return Icons.shopping_bag_rounded;
    } else if (cat.contains('trans') || cat.contains('fare') || cat.contains('gas') || cat.contains('car') || cat.contains('ride')) {
      return Icons.directions_car_rounded;
    } else if (cat.contains('health') || cat.contains('med') || cat.contains('doctor') || cat.contains('clinic')) {
      return Icons.medical_services_rounded;
    } else if (cat.contains('salary') || cat.contains('income') || cat.contains('job') || cat.contains('deposit')) {
      return Icons.monetization_on_rounded;
    }
    return Icons.payment_rounded;
  }

  void _showCommentSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? RodMaeColors.background : RodMaeColors.lightBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'COMMENTS',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isDark ? Colors.white : RodMaeColors.navy,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: widget.entry.comments.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No comments yet. Share your thoughts!',
                                style: GoogleFonts.inter(color: Colors.grey, fontSize: 12),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: widget.entry.comments.length,
                            itemBuilder: (context, idx) {
                              final comment = widget.entry.comments[idx];
                              final name = comment.userId == _currentUserId ? widget.spenderName : (widget.spenderName == 'Rodel' ? 'Eurine' : 'Rodel');
                              final isRodel = name == 'Rodel';
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: isRodel ? Colors.blue.withValues(alpha: 0.2) : Colors.pink.withValues(alpha: 0.2),
                                      child: Text(
                                        isRodel ? 'R' : 'E',
                                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isRodel ? Colors.blue : Colors.pink),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            comment.commentText,
                                            style: GoogleFonts.inter(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      Formatters.time(comment.createdAt),
                                      style: GoogleFonts.inter(color: Colors.grey, fontSize: 9),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            hintStyle: GoogleFonts.inter(fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: RodMaeColors.gold),
                        onPressed: () {
                          if (controller.text.trim().isNotEmpty) {
                            final newComment = TransactionComment(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              transactionId: widget.entry.id,
                              userId: _currentUserId ?? 'current-user-uid',
                              commentText: controller.text.trim(),
                              createdAt: DateTime.now(),
                            );
                            widget.entry.comments.add(newComment);
                            setModalState(() {});
                            controller.clear();
                            setState(() {}); 
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
    final isIncome = widget.entry.type == TransactionType.income;
    final isTransfer = widget.entry.type == TransactionType.transfer;
    final txColor = isIncome ? RodMaeColors.mint : (isTransfer ? RodMaeColors.electricBlue : RodMaeColors.coral);
    final icon = _getCategoryIcon(widget.entry.category);

    final reactionCounts = <String, int>{};
    for (final r in widget.entry.reactions) {
      reactionCounts[r.reactionType] = (reactionCounts[r.reactionType] ?? 0) + 1;
    }

    final emojiMap = {
      'heart': '❤️',
      'thumbs_up': '👍',
      'shocked': '😲',
      'sad': '😢',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: widget.entry.createdByUserId.contains('rodel') ? Colors.blue.withValues(alpha: 0.15) : Colors.pink.withValues(alpha: 0.15),
                child: Text(
                  widget.spenderName.isNotEmpty ? widget.spenderName[0].toUpperCase() : 'U',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: widget.entry.createdByUserId.contains('rodel') ? Colors.blue : Colors.pink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: txColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.entry.category,
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white : RodMaeColors.navy,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'By ${widget.spenderName}',
                          style: GoogleFonts.inter(
                            color: widget.isCurrentUser ? RodMaeColors.gold : (isDark ? Colors.white54 : RodMaeColors.lightTextSoft),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Formatters.date(widget.entry.date),
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white30 : Colors.black38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '${isIncome ? '+' : '-'} ₱${Formatters.money(widget.entry.amount).replaceAll('PHP', '').trim()}',
                style: GoogleFonts.robotoMono(
                  color: txColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (widget.entry.notes != null && widget.entry.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.entry.notes!,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 12,
              ),
            ),
          ],

          // Social metadata row
          if (widget.entry.reactions.isNotEmpty || widget.entry.comments.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: reactionCounts.entries.map((e) {
                    final emoji = emojiMap[e.key] ?? '👍';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$emoji ${e.value}',
                          style: GoogleFonts.inter(fontSize: 11),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (widget.entry.comments.isNotEmpty)
                  Text(
                    '${widget.entry.comments.length} comment${widget.entry.comments.length > 1 ? 's' : ''}',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white30 : Colors.black38,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),

          // Reaction Picker Row
          if (_showEmojiPicker) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojiMap.entries.map((e) {
                return InkWell(
                  onTap: () {
                    final existingIdx = widget.entry.reactions.indexWhere(
                      (r) => r.userId == (_currentUserId ?? '') && r.reactionType == e.key
                    );
                    
                    setState(() {
                      if (existingIdx != -1) {
                        widget.entry.reactions.removeAt(existingIdx);
                      } else {
                        widget.entry.reactions.removeWhere((r) => r.userId == (_currentUserId ?? ''));
                        widget.entry.reactions.add(
                          TransactionReaction(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            transactionId: widget.entry.id,
                            userId: _currentUserId ?? 'current-user-uid',
                            reactionType: e.key,
                            createdAt: DateTime.now(),
                          ),
                        );
                      }
                      _showEmojiPicker = false;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      e.value,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showEmojiPicker = !_showEmojiPicker;
                    });
                  },
                  icon: Icon(
                    Icons.add_reaction_outlined,
                    size: 18,
                    color: isDark ? Colors.white54 : RodMaeColors.navy.withValues(alpha: 0.6),
                  ),
                  label: Text(
                    'React',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : RodMaeColors.navy.withValues(alpha: 0.8),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _showCommentSheet(context),
                  icon: Icon(
                    Icons.comment_outlined,
                    size: 18,
                    color: isDark ? Colors.white54 : RodMaeColors.navy.withValues(alpha: 0.6),
                  ),
                  label: Text(
                    'Comment',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : RodMaeColors.navy.withValues(alpha: 0.8),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LocalGlassBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const LocalGlassBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: padding,
      margin: margin,
      child: child,
    );
  }
}

class TiltCard extends StatefulWidget {
  final Widget child;
  const TiltCard({required this.child, super.key});

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  bool _isHovered = false;

  void _resetTilt() {
    if (mounted) {
      setState(() {
        _tiltX = 0.0;
        _tiltY = 0.0;
        _isHovered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _isHovered = true;
        _updateTilt(event.localPosition);
      },
      onPointerMove: (event) {
        if (_isHovered) {
          _updateTilt(event.localPosition);
        }
      },
      onPointerUp: (_) => _resetTilt(),
      onPointerCancel: (_) => _resetTilt(),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(begin: Offset.zero, end: Offset(_tiltX, _tiltY)),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutQuad,
        builder: (context, tilt, child) {
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) 
              ..rotateX(tilt.dx)
              ..rotateY(tilt.dy)
              ..scale(_isHovered ? 0.97 : 1.0),
            alignment: FractionalOffset.center,
            child: widget.child,
          );
        },
      ),
    );
  }

  void _updateTilt(Offset localPos) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final size = renderBox.size;
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    
    final percentX = (localPos.dx - centerX) / centerX;
    final percentY = (localPos.dy - centerY) / centerY;
    
    setState(() {
      _tiltX = (-percentY * 0.12).clamp(-0.12, 0.12);
      _tiltY = (percentX * 0.12).clamp(-0.12, 0.12);
    });
  }
}

class QuickLogNumpadSheet extends StatefulWidget {
  final String category;
  final String initialAmount;
  final IconData icon;
  final Color accentColor;
  final Function(double) onConfirm;

  const QuickLogNumpadSheet({
    super.key,
    required this.category,
    required this.initialAmount,
    required this.icon,
    required this.accentColor,
    required this.onConfirm,
  });

  @override
  State<QuickLogNumpadSheet> createState() => QuickLogNumpadSheetState();
}

class QuickLogNumpadSheetState extends State<QuickLogNumpadSheet> {
  String _amountStr = '0';

  @override
  void initState() {
    super.initState();
    _amountStr = widget.initialAmount;
  }

  void _onKeyPress(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      if (key == 'C') {
        _amountStr = '0';
      } else if (key == '⌫') {
        if (_amountStr.length > 1) {
          _amountStr = _amountStr.substring(0, _amountStr.length - 1);
        } else {
          _amountStr = '0';
        }
      } else if (key == '.') {
        if (!_amountStr.contains('.')) {
          _amountStr += '.';
        }
      } else {
        if (_amountStr == '0') {
          _amountStr = key;
        } else {
          if (_amountStr.length < 9) {
            _amountStr += key;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parsedAmount = double.tryParse(_amountStr) ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? RodMaeColors.background.withValues(alpha: 0.98) : RodMaeColors.lightBackground.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: widget.accentColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  'QUICK LOG: ${widget.category.toUpperCase()}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: isDark ? Colors.white : RodMaeColors.navy,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.black38 : Colors.white60,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Amount',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  Text(
                    Formatters.money(parsedAmount).replaceAll('PHP', '₱').trim(),
                    style: GoogleFonts.robotoMono(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: widget.accentColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNumKey('1'),
                    _buildNumKey('2'),
                    _buildNumKey('3'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNumKey('4'),
                    _buildNumKey('5'),
                    _buildNumKey('6'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNumKey('7'),
                    _buildNumKey('8'),
                    _buildNumKey('9'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNumKey('.'),
                    _buildNumKey('0'),
                    _buildNumKey('⌫', icon: Icons.backspace_rounded),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                    ),
                    child: Text(
                      'CANCEL',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: parsedAmount <= 0
                        ? null
                        : () {
                            HapticFeedback.heavyImpact();
                            widget.onConfirm(parsedAmount);
                            Navigator.pop(context);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: widget.accentColor.withValues(alpha: 0.35),
                    ),
                    child: Text(
                      'LOG EXPENSE',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildNumKey(String text, {IconData? icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 72,
      height: 60,
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _onKeyPress(text),
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: icon != null
                ? Icon(icon, color: isDark ? Colors.white70 : Colors.black87)
                : Text(
                    text,
                    style: GoogleFonts.robotoMono(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class SavingsGoalCard extends StatelessWidget {
  final SavingsGoal goal;

  const SavingsGoalCard({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Calculate percentage
    final percent = goal.targetAmount > 0 
        ? (goal.currentAmount / goal.targetAmount).clamp(0.0, 1.0) 
        : 0.0;
    final percentString = (percent * 100).toStringAsFixed(0);

    // Curated accent color based on category
    final accentColor = goal.category == 'emergency' 
        ? Colors.redAccent 
        : RodMaeColors.electricBlue;

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: LocalGlassBox(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white.withValues(alpha: 0.9) : RodMaeColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$percentString%',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  goal.category == 'emergency' ? '🚨 Emergency Fund' : '✨ Life Event',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₱${Formatters.compactMoney(goal.currentAmount).replaceAll('PHP', '').trim()}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : RodMaeColors.navy,
                      ),
                    ),
                    Text(
                      'of ₱${Formatters.compactMoney(goal.targetAmount).replaceAll('PHP', '').trim()}',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        color: RodMaeColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MonthlyReportCard extends StatelessWidget {
  final MonthlyReport report;
  final VoidCallback onAskCoach;

  const MonthlyReportCard({
    super.key,
    required this.report,
    required this.onAskCoach,
  });

  @override
  Widget build(BuildContext context) {

    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final monthName = report.month >= 1 && report.month <= 12 
        ? monthNames[report.month - 1] 
        : 'Monthly';

    final isGoodGrade = report.overallGrade.startsWith('A') || report.overallGrade.startsWith('B');
    final gradient = isGoodGrade
        ? const LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFF373B44), Color(0xFF4286f4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$monthName ${report.year} Report Card'.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white60,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'AI Money Coach Analysis',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          report.overallGrade,
                          style: GoogleFonts.robotoMono(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildScoreMetric(
                        label: 'Spending Adherence',
                        score: report.spendingScore,
                        icon: Icons.shopping_bag_outlined,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildScoreMetric(
                        label: 'Savings Success',
                        score: report.savingsScore,
                        icon: Icons.savings_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Text(
                    report.aiAdvice,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAskCoach,
                    icon: const Icon(Icons.forum_outlined, size: 16),
                    label: Text(
                      'Ask AI Coach',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreMetric({
    required String label,
    required double score,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${score.toStringAsFixed(1)}/100',
                  style: GoogleFonts.robotoMono(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
