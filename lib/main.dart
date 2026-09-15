import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'attendance_mark_screen.dart';
import 'attendance_view_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const SKAttendanceHubApp(),
  );
}

class SKAttendanceHubApp extends StatelessWidget {
  const SKAttendanceHubApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SK ATTENDANCE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
      ),
      home: const AttendanceHubHome(),
    );
  }
}

class AttendanceHubHome extends StatelessWidget {
  const AttendanceHubHome({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SK ATTENDANCE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Image.asset(
              'assets/sk_new_logo.png',
              height: 90,
            ),
            const SizedBox(height: 20),
            const Text(
              'SK ATTENDANCE',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Attendance Management System',
              style: TextStyle(
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 35),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AttendanceTrackerScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.visibility,
                ),
                label: const Text(
                  'STAFF - VIEW ATTENDANCE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.login,
                ),
                label: const Text(
                  'ADMIN / TEAM LEADER LOGIN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String scriptUrl =
      'https://script.google.com/macros/s/AKfycbzHCmkMg-_e-GflpKI28XNQ0b7ECmq9TucAfnbVp1R6UhQLo7WYAsmCTTRsY06q2GbRxw/exec';

  final TextEditingController _usernameController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();

    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage(
        'Username and password are required.',
        Colors.orange,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse(
        '$scriptUrl'
        '?action=login'
        '&username=${Uri.encodeComponent(username)}'
        '&password=${Uri.encodeComponent(password)}',
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 20),
          );

      if (!mounted) return;

      if (response.statusCode != 200) {
        _showMessage(
          'Unable to connect to Google Sheet.',
          Colors.red,
        );
        return;
      }

      final body = response.body.trim();

      if (body.isEmpty) {
        _showMessage(
          'Empty server response.',
          Colors.red,
        );
        return;
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        _showMessage(
          'Invalid server response.',
          Colors.red,
        );
        return;
      }

      final data = Map<String, dynamic>.from(
        decoded,
      );

      if (data['success'] != true) {
        _showMessage(
          data['message']?.toString() ?? 'Invalid username or password.',
          Colors.red,
        );
        return;
      }

      final loggedUsername = data['username']?.toString() ?? username;

      final role = data['role']?.toString() ?? '';

      if (role != 'Admin' && role != 'Team Leader') {
        _showMessage(
          'Invalid user role.',
          Colors.red,
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceRoleHome(
            username: loggedUsername,
            role: role,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      _showMessage(
        'Unable to connect to Google Sheet.',
        Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(
    String message,
    Color color,
  ) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Login',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 25),
            Image.asset(
              'assets/sk_new_logo.png',
              height: 85,
            ),
            const SizedBox(height: 25),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(
                  Icons.lock,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                _login();
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _login,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.login,
                      ),
                label: const Text(
                  'LOGIN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AttendanceRoleHome extends StatelessWidget {
  final String username;
  final String role;

  const AttendanceRoleHome({
    super.key,
    required this.username,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          role,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(
                    Icons.person,
                  ),
                ),
                title: Text(
                  username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(role),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceMarkScreen(
                        username: username,
                        role: role,
                      ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.qr_code_scanner,
                ),
                label: const Text(
                  'MARK ATTENDANCE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AttendanceTrackerScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.visibility,
                ),
                label: const Text(
                  'VIEW ATTENDANCE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop();
              },
              icon: const Icon(
                Icons.logout,
              ),
              label: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
