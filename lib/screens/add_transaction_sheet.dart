import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../models/upcoming_payment.dart';
import '../models/wallet_constants.dart';
import '../services/finance_repository.dart';
import '../services/auth_service.dart';
import '../services/gemini_service.dart';
import '../core/constants.dart';
import '../widgets/particle_burst.dart';
import '../widgets/three_d_flip_success_card.dart';
import '../widgets/aesthetic_press_scale.dart';
import '../core/utils.dart';

class AddTransactionSheet extends StatefulWidget {
  final Function(Transaction)? onTransactionSaved;

  const AddTransactionSheet({
    super.key,
    this.onTransactionSaved,
  });

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagsController = TextEditingController();
  final _subCategoryController = TextEditingController();

  TransactionType _selectedType = TransactionType.expense;
  Wallet? _selectedWallet;
  Wallet? _destinationWallet;
  String _selectedCategory = 'Groceries';

  // Advanced toggles
  bool _isSplit = false;
  double _splitPercentage = 50.0; 

  bool _isRecurring = false;
  int _totalInstallments = 12;
  String _recurrenceInterval = 'monthly';

  // State loading indicators
  bool _loadingWallets = true;
  bool _saving = false;
  bool _scanning = false;
  bool _showSuccessOverlay = false;
  bool _isSynced = true;
  Transaction? _savedTransaction;
  List<Wallet> _wallets = [];

  final List<Map<String, dynamic>> _quickCategories = [
    {'emoji': '🛒', 'name': 'Groceries', 'color': Color(0xFF3B82F6)}, 
    {'emoji': '🍽️', 'name': 'Date Night', 'color': Color(0xFFEC4899)}, 
    {'emoji': '⚡', 'name': 'Utility Bills', 'color': Color(0xFFF59E0B)}, 
    {'emoji': '🏠', 'name': 'Housing/Rent', 'color': Color(0xFF6B7280)}, 
    {'emoji': '🚗', 'name': 'Gas & Transport', 'color': Color(0xFF10B981)}, 
    {'emoji': '🏥', 'name': 'Health & Medicine', 'color': Color(0xFFEF4444)}, 
    {'emoji': '💑', 'name': 'Shared Savings', 'color': Color(0xFF8B5CF6)}, 
    {'emoji': '👕', 'name': 'Clothes/Shopping', 'color': Color(0xFFE11D48)}, 
    {'emoji': '☕', 'name': 'Coffee & Snacks', 'color': Color(0xFFD97706)}, 
    {'emoji': '🎮', 'name': 'Entertainment/Streaming', 'color': Color(0xFF6366F1)}, 
    {'emoji': '🎁', 'name': 'Gifts & Tithes', 'color': Color(0xFF14B8A6)}, 
    {'emoji': '🐾', 'name': 'Pet Care', 'color': Color(0xFFF97316)}, 
  ];

  final List<Map<String, dynamic>> _incomeCategories = [
    {'emoji': '💼', 'name': 'Salary', 'color': Color(0xFF10B981)},
    {'emoji': '📈', 'name': 'Business', 'color': Color(0xFF3B82F6)},
    {'emoji': '📥', 'name': 'Inflow', 'color': Color(0xFFF59E0B)},
  ];

  final _particleBurstKey = GlobalKey<ParticleBurstState>();

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    _subCategoryController.dispose();
    super.dispose();
  }

  Future<void> _loadWallets() async {
    try {
      final wallets = await FinanceRepository.instance.fetchWallets();
      setState(() {
        _wallets = wallets;
        if (wallets.isNotEmpty) {
          _selectedWallet = wallets.first;
          if (wallets.length > 1) {
            _destinationWallet = wallets[1];
          } else {
            _destinationWallet = wallets.first;
          }
        }
        _loadingWallets = false;
      });
    } catch (e) {
      setState(() => _loadingWallets = false);
    }
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
        const SnackBar(content: Text('Extracting details with Gemini OCR...')),
      );

      final bytes = await image.readAsBytes();
      final extraction = await GeminiCompanionService.instance.scanReceipt(bytes);

      setState(() {
        _amountController.text = extraction.totalAmount.toStringAsFixed(2);
        final matchedCategory = _quickCategories.firstWhere(
          (cat) => cat['name']!.toLowerCase().contains(extraction.category.toLowerCase()) ||
                   extraction.category.toLowerCase().contains(cat['name']!.toLowerCase()),
          orElse: () => _quickCategories.first,
        );
        _selectedCategory = matchedCategory['name']!;
        _noteController.text = extraction.storeName;
      });

      messenger.showSnackBar(
        SnackBar(content: Text('Successfully parsed: ${extraction.storeName} - ₱${extraction.totalAmount}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Receipt scan failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Database Collision or Network Failure: $message',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: RodMaeColors.coral,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.trim();
    final double? amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      _showErrorSnackBar('Please enter a valid amount greater than zero.');
      return;
    }

    if (_selectedType == TransactionType.transfer) {
      if (_selectedWallet == null || _destinationWallet == null) {
        _showErrorSnackBar('Please select both source and destination accounts.');
        return;
      }
      if (_selectedWallet!.id == _destinationWallet!.id) {
        _showErrorSnackBar('Source and destination accounts cannot be the same.');
        return;
      }
    } else {
      if (_selectedWallet == null) {
        _showErrorSnackBar('Please select a wallet.');
        return;
      }
    }

    setState(() => _saving = true);
    final activePartner = PartnerIdentity.active.value.label;

    try {
      Transaction? primaryTx;
      bool isSyncedLocal = true;

      if (_selectedType == TransactionType.transfer) {
        final txFromId = UuidUtil.generate();
        final txToId = UuidUtil.generate();
        final txFrom = Transaction(
          id: txFromId,
          walletId: _selectedWallet!.id,
          createdByUserId: activePartner,
          type: TransactionType.transfer,
          amount: amount,
          categoryId: 'Transfer',
          date: DateTime.now(),
          notes: 'From ${_selectedWallet!.name} to ${_destinationWallet!.name}',
        );

        final txTo = Transaction(
          id: txToId,
          walletId: _destinationWallet!.id,
          createdByUserId: activePartner,
          type: TransactionType.transfer,
          amount: amount,
          categoryId: 'Transfer',
          date: DateTime.now(),
          notes: 'To ${_destinationWallet!.name} from ${_selectedWallet!.name}',
        );

        try {
          await FinanceRepository.instance.insertTransaction(txFrom);
          await FinanceRepository.instance.insertTransaction(txTo);
        } catch (syncErr) {
          isSyncedLocal = false;
          debugPrint('Transfer sync warning: $syncErr');
        }
        primaryTx = txFrom;
      } else {
        final txId = UuidUtil.generate();
        final transaction = Transaction(
          id: txId,
          walletId: _selectedWallet!.id,
          createdByUserId: activePartner,
          type: _selectedType,
          amount: amount,
          categoryId: _selectedCategory,
          date: DateTime.now(),
          notes: _subCategoryController.text.trim().isNotEmpty ? _subCategoryController.text.trim() : null,
          splits: (_selectedType == TransactionType.expense && _isSplit)
              ? [
                  TransactionSplit(
                    transactionId: txId,
                    userId: activePartner.toLowerCase() == 'rodel' ? 'marymae' : 'rodel',
                    amountOwed: amount * _splitPercentage / 100.0,
                    isSettled: false,
                  )
                ]
              : const [],
        );

        try {
          if (_selectedType == TransactionType.expense && _isSplit) {
            await FinanceRepository.instance.addSplitTransaction(transaction, _splitPercentage);
          } else {
            await FinanceRepository.instance.insertTransaction(transaction);
          }

          if (_selectedType == TransactionType.expense && _isRecurring) {
            final upcoming = UpcomingPayment(
              id: UuidUtil.generate(),
              coupleId: AppConfig.coupleId,
              title: '$_selectedCategory Installment Plan',
              amount: amount,
              dueDate: DateTime.now().add(const Duration(days: 30)),
              isRecurring: true,
              isInstallment: true,
              totalInstallments: _totalInstallments,
              currentInstallment: 1,
              recurrenceInterval: _recurrenceInterval,
            );
            await FinanceRepository.instance.insertUpcomingPayment(upcoming);
          }
        } catch (syncErr) {
          isSyncedLocal = false;
          debugPrint('Transaction sync warning: $syncErr');
        }
        primaryTx = transaction;
      }

      await HapticFeedback.heavyImpact();
      _particleBurstKey.currentState?.burst();
      setState(() {
        _savedTransaction = primaryTx;
        _isSynced = isSyncedLocal;
        _showSuccessOverlay = true;
        _saving = false;
      });

      await Future.delayed(const Duration(milliseconds: 1800));
      
      if (mounted) {
        widget.onTransactionSaved?.call(primaryTx!);
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _saving = false);
      _showErrorSnackBar(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return ParticleBurst(
      key: _particleBurstKey,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? RodMaeColors.background.withValues(alpha: 0.95) : RodMaeColors.lightBackground.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
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
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ADD TRANSACTION',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : RodMaeColors.navy,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          _buildTypeSelector(),
                          const SizedBox(height: 16),

                          _buildAmountInput(),
                          const SizedBox(height: 16),

                          if (_selectedType == TransactionType.transfer) ...[
                            _buildWalletSelector(
                              label: 'SOURCE ACCOUNT (FROM)',
                              selectedWallet: _selectedWallet,
                              onSelected: (w) => setState(() => _selectedWallet = w),
                            ),
                            const SizedBox(height: 12),
                            _buildWalletSelector(
                              label: 'DESTINATION ACCOUNT (TO)',
                              selectedWallet: _destinationWallet,
                              onSelected: (w) => setState(() => _destinationWallet = w),
                            ),
                          ] else ...[
                            _buildWalletSelector(
                              label: _selectedType == TransactionType.income ? 'DEPOSIT TO' : 'SELECT SOURCE WALLET',
                              selectedWallet: _selectedWallet,
                              onSelected: (w) => setState(() => _selectedWallet = w),
                            ),
                          ],
                          const SizedBox(height: 16),

                          if (_selectedType != TransactionType.transfer) ...[
                            Text(
                              _selectedType == TransactionType.income
                                  ? 'INCOME STREAM CATEGORY'
                                  : 'SELECT CATEGORY',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildCategorySelector(),
                            const SizedBox(height: 16),
                          ],

                          if (_selectedType == TransactionType.expense) ...[
                            Text(
                              'ADVANCED CONTROLS',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),

                            _buildSplitSection(),
                            const SizedBox(height: 12),

                            _buildInstallmentSection(),
                            const SizedBox(height: 16),
                          ],

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _noteController,
                                  style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                                  decoration: InputDecoration(
                                    hintText: 'Note / Store Name',
                                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _subCategoryController,
                                  style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                                  decoration: InputDecoration(
                                    hintText: 'Sub Category',
                                    prefixIcon: const Icon(Icons.category_outlined, size: 18),
                                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: _tagsController,
                            style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              hintText: 'Tags (comma separated, e.g. dinner, travel)',
                              prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                            ),
                          ),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              if (_selectedType == TransactionType.expense) ...[
                                ElevatedButton.icon(
                                  onPressed: _scanning ? null : _scanReceipt,
                                  icon: _scanning
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.qr_code_scanner_rounded),
                                  label: Text(_scanning ? 'SCANNING' : 'SCAN'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: RodMaeColors.goldDeep,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: AestheticPressScale(
                                  onTap: _saving ? null : _saveTransaction,
                                  child: ElevatedButton(
                                    onPressed: null, // Handled by AestheticPressScale
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: RodMaeColors.gold,
                                      foregroundColor: RodMaeColors.navy,
                                      disabledBackgroundColor: RodMaeColors.gold,
                                      disabledForegroundColor: RodMaeColors.navy,
                                      elevation: 4,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shadowColor: RodMaeColors.gold.withValues(alpha: 0.35),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: _saving
                                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: RodMaeColors.navy))
                                        : Text(
                                            'SAVE TRANSACTION',
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_showSuccessOverlay && _savedTransaction != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.85),
                    child: ThreeDFlipSuccessCard(
                      amount: _savedTransaction!.amount,
                      category: _savedTransaction!.categoryId ?? 'General',
                      walletName: _selectedWallet?.name ?? 'Shared Wallet',
                      notes: _savedTransaction!.notes,
                      isSynced: _isSynced,
                    ),
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _buildTypeButton(TransactionType.expense, 'EXPENSE', RodMaeColors.coral),
          _buildTypeButton(TransactionType.income, 'INCOME', RodMaeColors.mint),
          _buildTypeButton(TransactionType.transfer, 'TRANSFER', RodMaeColors.electricBlue),
        ],
      ),
    );
  }

  Widget _buildTypeButton(TransactionType type, String label, Color highlightColor) {
    final isSelected = _selectedType == type;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = type;
            if (type == TransactionType.income) {
              _selectedCategory = _incomeCategories.first['name'];
            } else if (type == TransactionType.expense) {
              _selectedCategory = _quickCategories.first['name'];
            } else {
              _selectedCategory = 'Transfer';
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? highlightColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? highlightColor.withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: isSelected ? highlightColor : RodMaeColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountInput() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white60,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '₱',
            style: GoogleFonts.robotoMono(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: RodMaeColors.gold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.robotoMono(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                color: RodMaeColors.gold,
              ),
              decoration: const InputDecoration(
                hintText: '0.00',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSelector({
    required String label,
    required Wallet? selectedWallet,
    required ValueChanged<Wallet> onSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingWallets) {
      return const SizedBox(
        height: 50,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: RodMaeColors.gold)),
      );
    }

    if (_wallets.isEmpty) {
      return Text('No wallets found', style: GoogleFonts.inter(color: RodMaeColors.textMuted));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _wallets.length,
            itemBuilder: (context, index) {
              final wallet = _wallets[index];
              final isSelected = selectedWallet?.id == wallet.id;
              final brand = PhilippineWalletConstants.getBrand(wallet.name);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white24 : brand.primaryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          brand.logoText,
                          style: GoogleFonts.robotoMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? Colors.white : brand.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        wallet.name.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      onSelected(wallet);
                    }
                  },
                  selectedColor: brand.primaryColor,
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(
                    color: isSelected ? brand.primaryColor : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                  ),
                  showCheckmark: false,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    final categories = _selectedType == TransactionType.income ? _incomeCategories : _quickCategories;

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat['name'];
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final catColor = cat['color'] as Color;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cat['emoji']!, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    cat['name']!.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedCategory = cat['name']!);
                }
              },
              selectedColor: catColor,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(
                color: isSelected ? catColor : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
              ),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSplitSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parsedAmount = double.tryParse(_amountController.text) ?? 0.0;
    final partnerShare = parsedAmount * (_splitPercentage / 100.0);
    final myShare = parsedAmount - partnerShare;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            title: Text(
              'SPLIT THIS BILL',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: isDark ? Colors.white : RodMaeColors.navy),
            ),
            subtitle: Text(
              'Partner will owe you a portion of this expense',
              style: GoogleFonts.inter(fontSize: 10, color: RodMaeColors.textMuted),
            ),
            value: _isSplit,
            activeTrackColor: RodMaeColors.gold,
            onChanged: (val) {
              setState(() => _isSplit = val);
            },
          ),
          if (_isSplit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Partner's Share",
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
                      ),
                      Text(
                        "${_splitPercentage.toInt()}%",
                        style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.w800, color: RodMaeColors.gold),
                      ),
                    ],
                  ),
                  Slider.adaptive(
                    value: _splitPercentage,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: RodMaeColors.gold,
                    inactiveColor: isDark ? Colors.white10 : Colors.black12,
                    onChanged: (val) {
                      setState(() => _splitPercentage = val);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPresetButton(50, '50/50'),
                      _buildPresetButton(60, '60/40'),
                      _buildPresetButton(70, '70/30'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'You pay: ₱${myShare.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white60 : Colors.black54),
                        ),
                        Text(
                          'Partner owes: ₱${partnerShare.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: RodMaeColors.mint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(double val, String label) {
    final isSelected = _splitPercentage == val;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => setState(() => _splitPercentage = val),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? RodMaeColors.gold.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? RodMaeColors.gold : (isDark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? RodMaeColors.gold : RodMaeColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildInstallmentSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            title: Text(
              'INSTALLMENT PLAN',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: isDark ? Colors.white : RodMaeColors.navy),
            ),
            subtitle: Text(
              'Convert this into multiple recurring payments',
              style: GoogleFonts.inter(fontSize: 10, color: RodMaeColors.textMuted),
            ),
            value: _isRecurring,
            activeTrackColor: RodMaeColors.gold,
            onChanged: (val) {
              setState(() => _isRecurring = val);
            },
          ),
          if (_isRecurring)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _totalInstallments,
                          style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                          dropdownColor: isDark ? RodMaeColors.background : Colors.white,
                          decoration: InputDecoration(
                            labelText: 'Tenure',
                            labelStyle: GoogleFonts.inter(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: [3, 6, 12, 24, 36].map((months) {
                            return DropdownMenuItem(
                              value: months,
                              child: Text('$months Mos'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _totalInstallments = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _recurrenceInterval,
                          style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white : Colors.black),
                          dropdownColor: isDark ? RodMaeColors.background : Colors.white,
                          decoration: InputDecoration(
                            labelText: 'Interval',
                            labelStyle: GoogleFonts.inter(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                            DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _recurrenceInterval = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
