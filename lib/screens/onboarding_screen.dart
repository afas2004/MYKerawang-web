import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_strings.dart';
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../widgets/brand/brand.dart';
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
  
  // State
  int _step = 0; // 0 = Identity, 1 = Contact & Role
  bool _isLoading = false;

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
    
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;

    try {
      // Update Profile with CRITICAL INFO
      await _supabase.from('profiles').upsert({
        'id': user!.id,
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'display_name': _nameCtrl.text.trim(),
        // Clubs register separately after sign-up (/clubs/register);
        // onboarding no longer writes club proof into the bio.
        'role': 'student',
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
                    padding: const EdgeInsets.all(KSpace.xl),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: KSpace.xl),
                              child: AppIllustration(AppIllo.welcome, size: 200),
                            ),
                          ),
                          Text(s.setupTitle, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: KSpace.s),
                          Text(s.setupSubtitle),
                          const SizedBox(height: KSpace.xxl),
                          
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
                          const SizedBox(height: KSpace.xl),
                          
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
                    padding: const EdgeInsets.all(KSpace.xl),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.contactDetails, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: KSpace.s),
                          Text(s.contactSubtitle),
                          const SizedBox(height: KSpace.xl),
                          
                          // PHONE NUMBER (optional until they sell)
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: s.whatsappNumber,
                              prefixIcon: const Icon(AppIcons.phone),
                              helperText: s.social.whatsappOptionalHelper,
                            ),
                          ),
                          
                          const SizedBox(height: KSpace.xxl),
                          const Divider(),
                          const SizedBox(height: KSpace.l),

                          // Clubs: a separate flow after sign-up.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => context.push('/clubs/register'),
                              icon: const Icon(AppIcons.people, size: 18),
                              label: Text(s.shell.registerClubLater),
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
              padding: const EdgeInsets.all(KSpace.xl),
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

    // Phone: full screen. ≥ 600: a centred card on a quiet surface.
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 600) return SafeArea(child: form);
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: scheme.surfaceContainerLow),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(KSpace.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
                  child: Material(
                    color: theme.colorScheme.surface,
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: KRadius.dialog,
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

/// Wordmark and a two-segment progress bar with "Step n of m".
class _StepHeader extends StatelessWidget {
  final int step;
  final int total;
  const _StepHeader({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.xl, KSpace.l, KSpace.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Flexible(child: Wordmark(fontSize: 20)),
              const Spacer(),
              const SizedBox(width: KSpace.m),
              Text(s.shell.stepOf.fill([step + 1, total]),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: KSpace.m),
          Semantics(
            label: s.shell.stepOf.fill([step + 1, total]),
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: KSpace.s),
                  Expanded(
                    child: AnimatedContainer(
                      duration: KMotion.of(context).slow,
                      curve: KMotion.curve,
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