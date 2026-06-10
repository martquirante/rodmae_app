import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in both email and password.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService.instance.signIn(email: email, password: password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome, ${PartnerIdentity.active.value.label}!'),
            backgroundColor: RodMaeColors.electricBlue,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/loading');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login Failed: Please check your credentials.'),
            backgroundColor: RodMaeColors.coral,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: RodMaeColors.getAppBackground(isDark)),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Beautiful Royal Monogram / Logo
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: RodMaeColors.gold,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: RodMaeColors.electricBlue.withValues(alpha: 0.25),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/app_logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: RodMaeColors.navy,
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: RodMaeColors.rose,
                          size: 54,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'OUR WEDDING PORTAL',
                style: GoogleFonts.inter(
                  color: RodMaeColors.sky,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Rodel & Eurine',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : RodMaeColors.lightText,
                ),
              ),
              const SizedBox(height: 28),
              GlassCard(
                borderColor: RodMaeColors.sky.withValues(alpha: isDark ? 0.12 : 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sign In to Continue',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : RodMaeColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Email
                    Text(
                      'EMAIL ADDRESS',
                      style: GoogleFonts.inter(
                        color: RodMaeColors.electricBlue,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'rodel@rodmae.com / marymae@rodmae.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Password
                    Text(
                      'PASSWORD',
                      style: GoogleFonts.inter(
                        color: RodMaeColors.electricBlue,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        hintText: 'rodmae2026',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryPillButton(
                        label: _loading ? 'LOGGING IN...' : 'LOG IN',
                        icon: Icons.vpn_key_rounded,
                        busy: _loading,
                        onPressed: _handleLogin,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Beautiful Hint Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: RodMaeColors.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: RodMaeColors.gold.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: RodMaeColors.gold, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'LOGIN INFORMATION:',
                          style: GoogleFonts.inter(
                            color: RodMaeColors.gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Email: rodel@rodmae.com (for Husband)\n• Email: marymae@rodmae.com (for Wife)\n• Password: rodmae2026',
                      style: GoogleFonts.robotoMono(
                        color: isDark ? Colors.white70 : RodMaeColors.lightTextSoft,
                        fontSize: 11,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'RodMae Wedding Companion App',
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white30 : RodMaeColors.lightTextSoft.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
