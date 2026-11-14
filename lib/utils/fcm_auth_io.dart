import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

dynamic obtenerCredencialesFcm(
  dynamic serviceAccountJson,
  http.Client client,
) async {
  final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
  final accessCredentials = await obtainAccessCredentialsViaServiceAccount(
    credentials,
    ['https://www.googleapis.com/auth/firebase.messaging'],
    client,
  );
  return {
    'token': accessCredentials.accessToken.data,
    'expiry': accessCredentials.accessToken.expiry,
  };
}
