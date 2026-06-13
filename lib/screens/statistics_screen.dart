import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/transaction.dart';
import '../services/finance_repository.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int _activeTouchedIndex = -1;

  // Map categories to consistent colors
  Color _getCategoryColor(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('grocer') || cat.contains('food') || cat.contains('ulam')) {
      return RodMaeColors.coral;
    } else if (cat.contains('date') || cat.contains('dine') || cat.contains('love')) {
      return RodMaeColors.rose;
    } else if (cat.contains('bill') || cat.contains('electric') || cat.contains('water') || cat.contains('utility')) {
      return RodMaeColors.violet;
    } else if (cat.contains('house') || cat.contains('rent')) {
      return RodMaeColors.amber;
    } else if (cat.contains('trans') || cat.contains('gas') || cat.contains('fare') || cat.contains('ride')) {
      return RodMaeColors.electricBlue;
    } else if (cat.contains('health') || cat.contains('med') || cat.contains('clinic')) {
      return Colors.cyan;
    } else if (cat.contains('savings') || cat.contains('vault') || cat.contains('invest')) {
      return RodMaeColors.mint;
    } else if (cat.contains('shop')) {
      return Colors.orange;
    }
    return RodMaeColors.textMuted;
  }

  String _getCategoryEmoji(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('grocer')) return '🛒';
    if (cat.contains('food') || cat.contains('dine')) return '🍽️';
    if (cat.contains('bill') || cat.contains('utility') || cat.contains('electric')) return '⚡';
    if (cat.contains('house') || cat.contains('rent')) return '🏠';
    if (cat.contains('trans') || cat.contains('gas') || cat.contains('ride')) return '🚗';
    if (cat.contains('health') || cat.contains('med')) return '🏥';
    if (cat.contains('savings') || cat.contains('vault') || cat.contains('invest')) return '💑';
    if (cat.contains('shop')) return '🛍️';
    return '💰';
  }

  String _formatMonthYear(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RodMaeColors.getAppBackground(isDark),
        ),
        child: SafeArea(
          child: StreamBuilder<List<Transaction>>(
            stream: FinanceRepository.instance.watchTransactions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: RodMaeColors.gold));
              }
              if (snapshot.hasError) {
                return _buildErrorState(snapshot.error.toString());
              }

              final transactions = snapshot.data ?? [];
              if (transactions.isEmpty) {
                return _buildEmptyState();
              }

              return _buildContent(transactions);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: RodMaeColors.coral.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: RodMaeColors.coral),
            const SizedBox(height: 16),
            Text(
              'Error loading analytics',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: RodMaeColors.textSoft, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() {}),
              style: ElevatedButton.styleFrom(backgroundColor: RodMaeColors.electricBlue),
              child: const Text('Retry'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('FINANCIAL ANALYTICS', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w900, fontSize: 20)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.analytics_outlined, size: 64, color: RodMaeColors.gold),
              const SizedBox(height: 20),
              Text(
                'No Financial Data Yet',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                'Add some expenses or income to view real-time breakdown graphs and cashflow trends.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: RodMaeColors.textSoft, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<Transaction> transactions) {
    final now = DateTime.now();
    // Filter to current month for localized analytics
    final currentMonthTxs = transactions.where((tx) => tx.date.month == now.month && tx.date.year == now.year).toList();

    // 1. Calculate category distribution (expenses only)
    final expenseTxs = currentMonthTxs.where((tx) => tx.type == TransactionType.expense).toList();
    final double totalExpense = expenseTxs.fold(0.0, (sum, tx) => sum + tx.amount);

    final Map<String, double> categorySums = {};
    for (final tx in expenseTxs) {
      // normalize category string for grouping
      String normalized = tx.category;
      if (normalized.contains(' - ')) {
        normalized = normalized.split(' - ').first;
      }
      categorySums[normalized] = (categorySums[normalized] ?? 0.0) + tx.amount;
    }

    final sortedCategories = categorySums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 2. Generate line spots for cumulative Cashflow Trend (Income vs Expense)
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final List<FlSpot> incomeSpots = [];
    final List<FlSpot> expenseSpots = [];

    double runningIncome = 0.0;
    double runningExpense = 0.0;

    // We calculate daily progress
    for (int day = 1; day <= daysInMonth; day++) {
      final dayTxs = currentMonthTxs.where((tx) => tx.date.day == day).toList();
      for (final tx in dayTxs) {
        if (tx.type == TransactionType.income) {
          runningIncome += tx.amount;
        } else if (tx.type == TransactionType.expense) {
          runningExpense += tx.amount;
        }
      }
      // Only plot up to today's date so we don't draw flat lines into the future
      if (day <= now.day) {
        incomeSpots.add(FlSpot(day.toDouble(), runningIncome));
        expenseSpots.add(FlSpot(day.toDouble(), runningExpense));
      }
    }

    // Edge case: if no spots, add a base spot to prevent crash
    if (incomeSpots.isEmpty) {
      incomeSpots.add(const FlSpot(1, 0));
    }
    if (expenseSpots.isEmpty) {
      expenseSpots.add(const FlSpot(1, 0));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('FINANCIAL ANALYTICS', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month indicator
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: RodMaeColors.electricBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: RodMaeColors.electricBlue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _formatMonthYear(now).toUpperCase(),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: RodMaeColors.textSoft,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // SECTION 1: Donut Chart (Expense Distribution)
            GlassBox(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expense Distribution',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Where your funds went this month',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: RodMaeColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (totalExpense == 0)
                    SizedBox(
                      height: 180,
                      child: Center(
                        child: Text(
                          'No expense logged this month.',
                          style: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        // Chart
                        Expanded(
                          flex: 5,
                          child: SizedBox(
                            height: 180,
                            child: PieChart(
                              PieChartData(
                                pieTouchData: PieTouchData(
                                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                    setState(() {
                                      if (!event.isInterestedForInteractions ||
                                          pieTouchResponse == null ||
                                          pieTouchResponse.touchedSection == null) {
                                        _activeTouchedIndex = -1;
                                        return;
                                      }
                                      _activeTouchedIndex = pieTouchResponse
                                          .touchedSection!.touchedSectionIndex;
                                    });
                                  },
                                ),
                                borderData: FlBorderData(show: false),
                                sectionsSpace: 4,
                                centerSpaceRadius: 50,
                                sections: List.generate(sortedCategories.length, (i) {
                                  final entry = sortedCategories[i];
                                  final isTouched = i == _activeTouchedIndex;
                                  final fontSize = isTouched ? 16.0 : 12.0;
                                  final radius = isTouched ? 36.0 : 28.0;
                                  final percentage = (entry.value / totalExpense) * 100;

                                  return PieChartSectionData(
                                    color: _getCategoryColor(entry.key),
                                    value: entry.value,
                                    title: '${percentage.toStringAsFixed(0)}%',
                                    radius: radius,
                                    titleStyle: GoogleFonts.inter(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Mini Legends list
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List.generate(
                              sortedCategories.take(4).length,
                              (i) {
                                final entry = sortedCategories[i];
                                final color = _getCategoryColor(entry.key);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // SECTION 2: Category Breakdown List
            GlassBox(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Category Breakdown',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedCategories.length,
                    separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 16),
                    itemBuilder: (context, index) {
                      final entry = sortedCategories[index];
                      final color = _getCategoryColor(entry.key);
                      final emoji = _getCategoryEmoji(entry.key);
                      final percent = totalExpense == 0 ? 0.0 : (entry.value / totalExpense) * 100;

                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(emoji, style: const TextStyle(fontSize: 18)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: percent / 100.0,
                                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                                    valueColor: AlwaysStoppedAnimation<Color>(color),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₱${Formatters.compactMoney(entry.value).replaceAll('PHP ', '')}',
                                style: GoogleFonts.robotoMono(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '${percent.toStringAsFixed(1)}%',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: RodMaeColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // SECTION 3: Cashflow Trend Chart
            GlassBox(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cashflow Trend',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cumulative cashflow throughout this month',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: RodMaeColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        lineTouchData: const LineTouchData(enabled: true),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (val, meta) {
                                // Show early, mid, late month days on axis
                                final intDay = val.toInt();
                                if (intDay == 1 || intDay == 15 || intDay == daysInMonth) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      'Day $intDay',
                                      style: GoogleFonts.inter(color: RodMaeColors.textMuted, fontSize: 10),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          // Income Line (Green)
                          LineChartBarData(
                            spots: incomeSpots,
                            isCurved: true,
                            color: RodMaeColors.mint,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: RodMaeColors.mint.withValues(alpha: 0.08),
                            ),
                          ),
                          // Expense Line (Red)
                          LineChartBarData(
                            spots: expenseSpots,
                            isCurved: true,
                            color: RodMaeColors.coral,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: RodMaeColors.coral.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendIndicator(RodMaeColors.mint, 'Cumulative Income'),
                      const SizedBox(width: 24),
                      _buildLegendIndicator(RodMaeColors.coral, 'Cumulative Spent'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendIndicator(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
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
