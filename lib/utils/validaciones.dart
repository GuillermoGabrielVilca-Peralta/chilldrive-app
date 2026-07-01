// Validaciones puras de formularios (sin dependencias de UI → testeables).

/// Regex de correo: algo + @ + dominio + "." + TLD, sin espacios.
/// Validación básica del lado cliente; el backend valida de nuevo con [EmailAddress].
final _correoRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// True si [correo] tiene un formato de email razonable. Recorta espacios.
bool esCorreoValido(String correo) => _correoRegex.hasMatch(correo.trim());
