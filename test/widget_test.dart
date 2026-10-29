import 'package:flutter_test/flutter_test.dart';
import 'package:fulbito/main.dart';

void main() {
  testWidgets('Carga inicial de la app', (WidgetTester tester) async {
    // Construye la aplicación Fulbito
    await tester.pumpWidget(const FulbitoApp());

    // Verifica que se muestre el texto de bienvenida
    expect(find.text('Fulbito App'), findsOneWidget);
  });
}