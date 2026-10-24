import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';

// ── Validaciones (campos vacíos y formato de correo) ─────────
final _reCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validarNombre(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'El nombre es obligatorio';
  if (t.length > 100) return 'Máximo 100 caracteres';
  return null;
}

String? validarCorreo(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'El correo es obligatorio';
  if (t.length > 100 || !_reCorreo.hasMatch(t)) {
    return 'Correo no válido (ejemplo: nombre@correo.com)';
  }
  return null;
}

String? validarDireccion(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'La dirección es obligatoria';
  if (t.length > 200) return 'Máximo 200 caracteres';
  return null;
}

/// Perfil del cliente: validación de campos vacíos y formato de correo.
class PerfilClienteScreen extends StatefulWidget {
  final String apiBase;

  PerfilClienteScreen({super.key, required this.apiBase});

  @override
  State<PerfilClienteScreen> createState() => _PerfilClienteScreenState();
}

class _PerfilClienteScreenState extends State<PerfilClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Datos válidos.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Mi perfil'),
      ),
      body: BoundedContent(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(Session.username ?? 'Cliente',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Todos los campos son obligatorios.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: _nombreCtrl,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(Icons.person_outline, size: 17),
                      ),
                      validator: validarNombre,
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: _correoCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.mail_outline, size: 17),
                      ),
                      validator: validarCorreo,
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: _direccionCtrl,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _guardar(),
                      decoration: InputDecoration(
                        labelText: 'Dirección',
                        prefixIcon: Icon(Icons.location_on_outlined, size: 17),
                      ),
                      validator: validarDireccion,
                    ),
                    SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _guardar,
                      icon: Icon(Icons.save_outlined, size: 18),
                      label: Text('Guardar cambios'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
