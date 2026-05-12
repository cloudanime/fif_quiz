import 'dart:convert';

void main() {
  String optionsData = '{"A": "Apostle Ezekiel Guti", "B": "Evangelist from Ngaone"}';
  Map<String, dynamic> options = {};
  
  try {
    dynamic decoded = jsonDecode(optionsData);
    while (decoded is String) {
      decoded = jsonDecode(decoded);
    }
    options = Map<String, dynamic>.from(decoded);
  } catch (e) {
    print('Error: $e');
  }
  
  print('Parsed options: $options');
  
  print('A: ${options['A']}');
  print('a: ${options['a']}');
  print('Apostle: ${options['Apostle']}');
}
