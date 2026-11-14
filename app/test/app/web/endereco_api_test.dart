import 'package:calculadoradarf/app/web/endereco_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const esperado = 'https://calculadora-darf-web.vercel.app/api';

  test('página no host da Vercel usa a própria origem', () {
    expect(
      enderecoApi(Uri.parse('https://calculadora-darf-web.vercel.app/#/')),
      Uri.parse(esperado),
    );
  });

  test('outros hosts usam a Vercel', () {
    expect(
      enderecoApi(Uri.parse('https://calculadora-darf.onrender.com/')),
      Uri.parse(esperado),
    );
    expect(
      enderecoApi(Uri.parse('http://localhost:5000/')),
      Uri.parse(esperado),
    );
  });
}
