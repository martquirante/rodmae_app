import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/vault_document.dart';
import '../models/meal_plan.dart';
import '../services/supabase_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/common_widgets.dart';
import '../widgets/advanced_loading_effect.dart';

class VaultMemoriesScreen extends StatefulWidget {
  const VaultMemoriesScreen({super.key});

  @override
  State<VaultMemoriesScreen> createState() => _VaultMemoriesScreenState();
}

class _VaultMemoriesScreenState extends State<VaultMemoriesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return RodMaePageFrame(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: SegmentedSwitcher(
              labels: const ['Docs', 'Checklist', 'Memories'],
              icons: const [
                Icons.lock_outline_rounded,
                Icons.check_circle_outline_rounded,
                Icons.photo_library_outlined,
              ],
              selected: _tab,
              onSelected: (value) => setState(() => _tab = value),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                VaultDocumentsTab(),
                GoalsChecklistTab(),
                MemoriesCoverFlowTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VaultDocumentsTab extends StatefulWidget {
  const VaultDocumentsTab({super.key});

  @override
  State<VaultDocumentsTab> createState() => _VaultDocumentsTabState();
}

class _VaultDocumentsTabState extends State<VaultDocumentsTab> {
  late Future<List<VaultDocument>> _future;

  @override
  void initState() {
    super.initState();
    _future = SupabaseWeddingRepository.instance.fetchVaultDocuments();
  }

  void _refresh() {
    setState(() {
      _future = SupabaseWeddingRepository.instance.fetchVaultDocuments();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<VaultDocument>>(
      future: _future,
      builder: (context, snapshot) {
        final docs = snapshot.data ?? <VaultDocument>[];
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 112),
          children: [
            GlassCard(
              gradient: isDark ? const LinearGradient(
                colors: [Color(0xFF2D1B69), Color(0xFF0A192F)],
              ) : null,
              borderColor: RodMaeColors.sky.withValues(alpha: isDark ? 0.18 : 0.4),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: RodMaeColors.sky),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Encrypted Lock Vault',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Safe and secure digital vault',
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white60 : RodMaeColors.lightTextSoft,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    color: RodMaeColors.sky,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.03),
              borderColor: RodMaeColors.sky.withValues(alpha: isDark ? 0.12 : 0.4),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    color: RodMaeColors.electricBlue,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Private Vault Storage',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your private memories folder',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white.withValues(alpha: 0.45) : RodMaeColors.lightTextSoft,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AdvancedLoadingEffect(
                  isLoading: true,
                  placeholder: Column(
                    children: List.generate(
                      3,
                      (index) => Container(
                        height: 72,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  child: const SizedBox(height: 236),
                ),
              )
            else if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    'No documents stored here yet.\nUpload files to save PDFs & images!',
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
              ...docs.map(VaultDocumentTile.new),
          ],
        );
      },
    );
  }
}

class VaultDocumentTile extends StatelessWidget {
  final VaultDocument doc;

  const VaultDocumentTile(this.doc, {super.key});

  Future<void> _copyLink(BuildContext context) async {
    final link = doc.signedUrl;
    if (link == null || link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No signed link available yet.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Secure link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: RodMaeColors.electricBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: RodMaeColors.electricBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${doc.sizeLabel} - uploaded ${Formatters.date(doc.uploadedAt)}',
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white.withValues(alpha: 0.45) : RodMaeColors.lightTextSoft,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy secure link',
            onPressed: () => _copyLink(context),
            icon: const Icon(Icons.download_rounded),
            color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
          ),
          const Icon(Icons.delete_outline_rounded, color: RodMaeColors.coral),
        ],
      ),
    );
  }
}

class GoalsChecklistTab extends StatefulWidget {
  const GoalsChecklistTab({super.key});

  @override
  State<GoalsChecklistTab> createState() => _GoalsChecklistTabState();
}

class _GoalsChecklistTabState extends State<GoalsChecklistTab> {
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addGoal() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _adding) {
      return;
    }
    setState(() => _adding = true);
    try {
      await SupabaseWeddingRepository.instance.insertChecklistItem(text, 'Newlyweds');
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New adventure checklist item added!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add goal: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _toggleGoal(String id, bool completed) async {
    try {
      await SupabaseWeddingRepository.instance.toggleChecklistItem(id, completed);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return StreamBuilder<List<GoalItem>>(
      stream: SupabaseWeddingRepository.instance.watchChecklist(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AdvancedLoadingEffect(
            isLoading: true,
            placeholder: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: 4,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (_, index) => Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            child: const SizedBox.expand(),
          );
        }

        final goals = snapshot.data ?? <GoalItem>[];
        final completed = goals.where((goal) => goal.completed).length;

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 112),
          children: [
            GlassCard(
              gradient: isDark ? const LinearGradient(
                colors: [Color(0xFF1F1B5F), Color(0xFF0A192F)],
              ) : null,
              borderColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Newlyweds Adventure Checklist',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mark accomplished milestones we build as newlyweds.',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white60 : RodMaeColors.lightTextSoft,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: goals.isEmpty ? 0 : completed / goals.length,
                      minHeight: 7,
                      color: RodMaeColors.electricBlue,
                      backgroundColor: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _addGoal(),
                    decoration: const InputDecoration(
                      hintText: 'Add to newlyweds bucket...',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FloatingActionButton.small(
                  onPressed: _adding ? null : _addGoal,
                  backgroundColor: RodMaeColors.electricBlue,
                  foregroundColor: Colors.white,
                  child: _adding
                      ? AdvancedLoadingEffect(
                          isLoading: true,
                          shape: BoxShape.circle,
                          placeholder: Container(
                            width: 15,
                            height: 15,
                            decoration: const BoxDecoration(
                              color: Colors.white38,
                              shape: BoxShape.circle,
                            ),
                          ),
                          child: const SizedBox(width: 15, height: 15),
                        )
                      : const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (goals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    'No adventure milestones found.\nType one above to start your checklist!',
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
              ...List.generate(goals.length, (index) {
                final goal = goals[index];
                return GoalTile(
                  goal: goal,
                  onChanged: (value) => _toggleGoal(goal.id, value),
                );
              }),
          ],
        );
      },
    );
  }
}

class GoalTile extends StatelessWidget {
  final GoalItem goal;
  final ValueChanged<bool> onChanged;

  const GoalTile({
    required this.goal,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      borderColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
      child: CheckboxListTile(
        value: goal.completed,
        onChanged: (value) => onChanged(value ?? false),
        activeColor: RodMaeColors.electricBlue,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(
          goal.title,
          style: GoogleFonts.inter(
            color: goal.completed 
                ? (isDark ? Colors.white38 : Colors.black26) 
                : (isDark ? Colors.white : RodMaeColors.lightText),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            decoration: goal.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        secondary: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.8),
            borderRadius: BorderRadius.circular(14),
            border: isDark ? null : Border.all(color: Colors.black.withValues(alpha: 0.1)),
          ),
          child: Text(
            goal.category,
            style: GoogleFonts.inter(
              color: isDark ? Colors.white60 : RodMaeColors.lightTextSoft,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class MemoriesCoverFlowTab extends StatefulWidget {
  const MemoriesCoverFlowTab({super.key});

  @override
  State<MemoriesCoverFlowTab> createState() => _MemoriesCoverFlowTabState();
}

class _MemoriesCoverFlowTabState extends State<MemoriesCoverFlowTab> {
  late final PageController _pageController;
  double _page = 0;

  static const memories = <MemoryItem>[
    MemoryItem(
      imageUrl: 'https://images.unsplash.com/photo-1519741497674-611481863552?w=900&q=85',
      title: 'Engagement Proposal',
      dateLabel: '2026-03-12',
      caption: 'The promise that started the final countdown to forever.',
    ),
    MemoryItem(
      imageUrl: 'https://images.unsplash.com/photo-1465495976277-4387d4b0b4c6?w=900&q=85',
      title: 'Pre-wedding Photoshoot',
      dateLabel: '2026-05-15',
      caption: 'Clean sapphire tones, polished portraits, and calm joy.',
    ),
    MemoryItem(
      imageUrl: 'https://images.unsplash.com/photo-1511285560929-80b456fea0bc?w=900&q=85',
      title: 'Wedding Nuptials',
      dateLabel: '2026-06-03',
      caption: 'The day Rodel and Eurine become one household.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.73);
    _pageController.addListener(() {
      if (mounted) {
        setState(() => _page = _pageController.page ?? 0);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: GlassCard(
            gradient: isDark ? const LinearGradient(
              colors: [Color(0xFF2D1B69), Color(0xFF0A192F)],
            ) : null,
            borderColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
            child: Row(
              children: [
                const Icon(Icons.photo_library_outlined, color: RodMaeColors.sky),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Photo Memories Vault',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Swipe through cover-flow memories in depth space.',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white60 : RodMaeColors.lightTextSoft,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: memories.length,
            itemBuilder: (context, index) {
              final diff = index - _page;
              final scale = (1 - diff.abs() * 0.12).clamp(0.78, 1.0);
              final opacity = (1 - diff.abs() * 0.34).clamp(0.42, 1.0);
              return Opacity(
                opacity: opacity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0014)
                    ..translateByDouble(diff * -16, 0, diff.abs() * -70, 1)
                    ..rotateY(diff * -0.42)
                    ..scaleByDouble(scale, scale, scale, 1),
                  child: MemoryCoverCard(
                    memory: memories[index],
                    active: index == _page.round(),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 112),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(memories.length, (index) {
              final active = index == _page.round();
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: active ? 24 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: active ? RodMaeColors.electricBlue : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class MemoryCoverCard extends StatelessWidget {
  final MemoryItem memory;
  final bool active;

  const MemoryCoverCard({
    required this.memory,
    required this.active,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: active
              ? RodMaeColors.gold.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.08),
          width: active ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: active
                ? RodMaeColors.electricBlue.withValues(alpha: 0.28)
                : Colors.black.withValues(alpha: 0.25),
            blurRadius: active ? 26 : 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              memory.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) {
                  return child;
                }
                return AdvancedLoadingEffect(
                  isLoading: true,
                  placeholder: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white12,
                    ),
                  ),
                  child: Container(
                    color: Colors.transparent,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const DecoratedBox(
                  decoration: BoxDecoration(color: RodMaeColors.navy),
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.white38,
                    size: 48,
                  ),
                );
              },
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                    stops: const [0.42, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.title,
                    style: GoogleFonts.playfairDisplay(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    memory.dateLabel,
                    style: GoogleFonts.robotoMono(
                      color: RodMaeColors.sky,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    memory.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
