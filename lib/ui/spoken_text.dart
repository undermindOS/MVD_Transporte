/// Uppercase API names ("PUNTA CARRETAS", "AV ITALIA y PROPIOS") in title
/// case for screen readers, which may otherwise spell uppercase words
/// letter by letter. Particles stay lowercase: a capital "Y" between two
/// streets can be read as the letter. The screen keeps the uppercase text.
String spokenName(String text) {
  final words = text.toLowerCase().split(' ');
  return [
    for (var i = 0; i < words.length; i++)
      i > 0 && _particles.contains(words[i]) || words[i].isEmpty
          ? words[i]
          : words[i][0].toUpperCase() + words[i].substring(1),
  ].join(' ');
}

const _particles = {
  'a', 'al', 'de', 'del', 'e', 'el', 'en', 'la', 'las', 'los', 'o', 'y',
};
