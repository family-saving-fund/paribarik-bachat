/// Presentation helpers for Nepali (Devanagari) digits.
/// Keep Firestore values and numeric calculations in Western digits; convert
/// only the text shown to users.
String toNepaliDigits(Object? value) {
  final text = value?.toString() ?? '';
  const western = '0123456789';
  const nepali = '०१२३४५६७८९';
  return text.split('').map((character) {
    final index = western.indexOf(character);
    return index < 0 ? character : nepali[index];
  }).join();
}

String toWesternDigits(Object? value) {
  final text = value?.toString() ?? '';
  const nepali = '०१२३४५६७८९';
  const western = '0123456789';
  return text.split('').map((character) {
    final index = nepali.indexOf(character);
    return index < 0 ? character : western[index];
  }).join();
}
