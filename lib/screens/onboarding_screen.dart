import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_strings.dart';
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../theme/app_themes.dart';
import '../widgets/kerawang_motif.dart';
import '../widgets/lattice_placeholder.dart';
import '../widgets/shell_actions.dart';
import '../language_cubit.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  
  // FIX: Page Controller to handle sliding
  final PageController _pageController = PageController();

  // Controllers
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(); // <--- NEW: Phone
  final _clubReasonCtrl = TextEditingController(); // <--- NEW: For Club verification
  
  // State
  int _step = 0; // 0 = Identity, 1 = Contact & Role
  bool _isLoading = false;
  bool _isClub = false; 

  // Username Logic
  String? _usernameError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadExistingProfile(); // <--- NEW: Check for existing data
  }

  Future<void> _loadExistingProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    // Fetch what we already know about the user
    final data = await _supabase
        .from('profiles')
        .select('display_name, username')
        .eq('id', user.id)
        .maybeSingle();

    // Phone is private (profile_contacts, owner-only).
    try {
      final contact = await _supabase
          .from('profile_contacts')
          .select('phone_number')
          .eq('user_id', user.id)
          .maybeSingle();
      final phone = contact?['phone_number'];
      if (phone is String && mounted) _phoneCtrl.text = phone;
    } catch (e) {
      debugPrint("Error loading contact details: $e");
    }
    
    if (data != null && mounted) {
      setState(() {
        // Pre-fill fields so they don't have to type it again
        _nameCtrl.text = data['display_name'] ?? ''; 
        
        // If they managed to set a username before but got stuck, load it too
        if (data['username'] != null) {
          _usernameCtrl.text = data['username'];
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _clubReasonCtrl.dispose();
    super.dispose();
  }

  // --- VALIDATION LOGIC ---
  void _onUsernameChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (value.length < 3) return;
      
      final res = await _supabase.from('profiles').select('id').eq('username', value).maybeSingle();
      if (mounted) {
        setState(() {
          _usernameError = res != null ? context.l10nRead.usernameTakenShort : null;
        });
      }
    });
  }

  Future<void> _finishOnboarding() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usernameError != null) return;
    
    // Club Verification Check
    if (_isClub && _clubReasonCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10nRead.clubDetailsNeeded)));
      return;
    }

    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;

    try {
      // Update Profile with CRITICAL INFO
      await _supabase.from('profiles').upsert({
        'id': user!.id,
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'display_name': _nameCtrl.text.trim(),
        'role': _isClub ? 'club_pending' : 'student',
        // We save the club justification in 'bio' or a separate column for admin review
        'bio': _isClub ? "Club Verification: ${_clubReasonCtrl.text}" : null,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Optional here; create_listing asks for it before selling.
      final phone = _phoneCtrl.text.trim();
      if (phone.isNotEmpty) {
        await _supabase.from('profile_contacts').upsert({
          'user_id': user.id,
          'phone_number': phone,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
      }

      if (mounted) {
        // Go to Home (router replaces the stack)
        context.go('/home');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10nRead.errorWithDetail.fill([e]))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _nextPage() {
    // Validate Step 1 before moving
    if (_step == 0) {
      if (_usernameCtrl.text.isEmpty || _nameCtrl.text.isEmpty || _usernameError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10nRead.fixErrorsFirst)));
        return;
      }
    }

    setState(() => _step++);
    _pageController.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _prevPage() {
    setState(() => _step--);
    _pageController.animateToPage(_step, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;

    final form = Form(
        key: _formKey,
        child: Column(
          children: [
            _StepHeader(step: _step, total: 2),

            Expanded(
              child: PageView(
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                controller: _pageController, // FIX: Controller attached
                children: [
                  // --- STEP 1: IDENTITY ---
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.setupTitle, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(s.setupSubtitle),
                          const SizedBox(height: 32),
                          
                          // Username
                          TextFormField(
                            controller: _usernameCtrl,
                            decoration: InputDecoration(
                              labelText: s.username,
                              prefixText: "@",
                              errorText: _usernameError,
                              helperText: s.usernameHelper,
                            ),
                            onChanged: _onUsernameChanged,
                            validator: (v) => (v!.length < 3) ? s.usernameMin : null,
                          ),
                          const SizedBox(height: 24),
                          
                          // Display Name
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: InputDecoration(
                              labelText: s.displayName,
                              helperText: s.displayNameHelper,
                            ),
                            validator: (v) => v!.isEmpty ? s.required : null,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- STEP 2: CONTACT & ROLE ---
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.contactDetails, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(s.contactSubtitle),
                          const SizedBox(height: 24),
                          
                          // PHONE NUMBER (optional until they sell)
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: s.whatsappNumber,
                              prefixIcon: const Icon(Icons.phone),
                              helperText: s.social.whatsappOptionalHelper,
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 16),

                          // CLUB TOGGLE
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: _isClub ? scheme.primary : scheme.outlineVariant),
                              borderRadius: BorderRadius.circular(12),
                              color: _isClub ? scheme.primary.withValues(alpha: 0.05) : null,
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(s.registeringClub),
                                  subtitle: Text(s.registeringClubSub),
                                  value: _isClub,
                                  onChanged: (val) => setState(() => _isClub = val),
                                  secondary: const Icon(Icons.groups),
                                ),
                                
                                // Verification Field (Only if Club is ON)
                                if (_isClub) ...[
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _clubReasonCtrl,
                                    decoration: InputDecoration(
                                      labelText: s.clubReference,
                                      helperText: s.clubReferenceHelper,
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // BOTTOM BUTTONS
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(onPressed: _prevPage, child: Text(s.back)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _isLoading ? null : () {
                      if (_step == 0) {
                        _nextPage();
                      } else {
                        _finishOnboarding();
                      }
                    },
                    style: FilledButton.styleFrom(minimumSize: const Size(120, 50)),
                    child: _isLoading 
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                      : Text(_step == 0 ? s.next : s.finish),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

    // Phone: full screen. ≥ 600: a centred card on a lattice backdrop.
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 600) return SafeArea(child: form);
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: ColoredBox(
                color: scheme.surfaceContainerLow,
                child: LatticePlaceholder(color: scheme.tertiary, cell: 32, opacity: 0.18),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
                  child: Material(
                    color: theme.scaffoldBackgroundColor,
                    elevation: 1,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: kerawangCut,
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: form,
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Wordmark, motif and a two-segment progress bar with "Step n of m".
class _StepHeader extends StatelessWidget {
  final int step;
  final int total;
  const _StepHeader({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(child: Wordmark(fontSize: 22)),
              const SizedBox(width: 12),
              const KerawangDivider(size: 6),
              const Spacer(),
              const SizedBox(width: 12),
              Text(s.shell.stepOf.fill([step + 1, total]),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: s.shell.stepOf.fill([step + 1, total]),
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= step ? scheme.primary : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}