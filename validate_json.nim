proc main() =
  asm """
  var fs = require('fs');
  JSON.parse(fs.readFileSync('packages.json', 'utf8'));
  """
main()
