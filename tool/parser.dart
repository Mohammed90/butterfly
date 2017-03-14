import 'package:charcode/charcode.dart';

/// A proof of concept rewriter for simple XML like expressions.
///
///
///     new Dx('<div>${_foo}</div>'); =>
///       new div()([_foo]);
///
///     new Dx('''
///     <myElement bar=${fizz} bazz={2}>
///       <div>Foo</div>
///     </myElement>
///     '''); =>
///
///      new MyElement(bar=fizz, bazz=2)([
///        new Div()(["Foo"]),
///      ]);
///
///      new Dx('''
///        <div>
///           "This is a text node"
///           "${localTextNode}"
///        </div>
///      '''); =>
///
///      div()([text("this is a text node"), text(localTextNode)])
///
///      new Dx('<my-element></my-element>'); =>
///
///      new Element('my-element')();
///
class Parser {
  List<Node> _nodes;
  List<int> _runes;
  int _index;

  Parser();

  int get peek => _runes[_index];

  String parse(String source) {
    _nodes = <Node>[];
    _runes = source.runes.toList();
    _index = 0;
    consumeWhitespace();
    while (true) {
      consumeWhitespace();
      if (isDone()) {
        break;
      }
      switch (peek) {
        case $open_angle:
          consume();
          parseElement();
          break;
        case $dollar:
          parseFragment();
          break;
        case $double_quote:
          parseText();
          break;
        default:
          throw new Exception('Illegal char: ${new String.fromCharCode(peek)}');
      }
    }
    return ' ${_nodes.single}';
  }

  /// Parses "......" into a text node.
  void parseText() {
    final buffer = <int>[$double_quote];
    expect($double_quote);
    while (peek != $double_quote) {
      buffer.add(peek);
      consume();
    }
    expect($double_quote);
    buffer.add($double_quote);
    _nodes.add(new Text()..value = new String.fromCharCodes(buffer));
  }

  /// Parses ${...} into a fragment which is assumed to be either
  /// a node or a list of nodes.
  void parseFragment() {
    final buffer = <int>[];
    expect($dollar);
    expect($open_brace);
    while (peek != $close_brace) {
      buffer.add(peek);
      consume();
    }
    expect($close_brace);
    _nodes.add(new Fragment()..value = new String.fromCharCodes(buffer));
  }

  /// Parsers the start of `<` or `</`
  void parseElement() {
    if (peek == $slash) {
      consume();
      parseClosingNode();
    } else {
      parseOpeningNode();
    }
  }

  /// Parses the name of an opening element `<my-element` or `<MyClass`
  void parseOpeningNode() {
    consumeWhitespace();
    if (isLowerCase(peek)) {
      _nodes.add(new Constructor()
        ..name = parseElementName()
        ..isElement = true);
    } else {
      _nodes.add(new Constructor()
        ..name = parseClassName()
        ..isElement = false);
    }
    parseArguments();
  }

  /// Parses the attributes of an xml node into [Argument]
  void parseArguments() {
    while (true) {
      consumeWhitespace();
      if (peek == $slash) {
        consume();
        expect($close_angle);
        break;
      } else if (peek == $close_angle) {
        consume();
        break;
      } else {
        // TODO: replace this with a more accurate procedure that handles spaces.
        final name = <int>[];
        final value = <int>[];
        while (peek != $equal) {
          name.add(peek);
          consume();
        }
        expect($equal);
        expect($dollar);
        expect($open_brace);
        while (peek != $close_brace) {
          value.add(peek);
          consume();
        }
        expect($close_brace);
        (_nodes.last as Constructor).arguments.add(new Argument()
          ..name = new String.fromCharCodes(name)
          ..value = new String.fromCharCodes(value));
      }
    }
  }

  void parseClosingNode() {
    final name = isLowerCase(peek) ? parseElementName() : parseClassName();
    consumeWhitespace();
    expect($close_angle);
    final parent = _nodes.lastWhere((node) => node.name == name);
    Node removed;
    do {
      removed = _nodes.removeLast();
      if (parent != removed) {
        parent.children.add(removed);
      } else {
        _nodes.add(parent);
      }
    } while (removed != parent);
  }

  /// Parses the name of a widget constructor like `_PrivateClass` or `Foo123`.
  String parseClassName() {
    final buffer = new StringBuffer();
    if (isUpperCase(peek) || peek == $underscore) {
      buffer.writeCharCode(peek);
      consume();
    } else {
      throw new Exception(
          'expected class name but found ${new String.fromCharCode(peek)}');
    }
    while (isDartCase(peek)) {
      buffer.writeCharCode(peek);
      consume();
    }
    return buffer.toString();
  }

  /// Parses the name of an html or polymer element like `div` or `my-element`
  String parseElementName() {
    final buffer = new StringBuffer();
    if (isLowerCase(peek)) {
      buffer.writeCharCode(peek);
      consume();
    } else {
      throw new Exception('');
    }
    while (isXmlCase(peek)) {
      buffer.writeCharCode(peek);
      consume();
    }
    return buffer.toString();
  }

  void consumeWhitespace() {
    while (!isDone() &&
        (peek == $space || peek == $tab || peek == $lf || peek == $vt)) {
      consume();
    }
  }

  void expect(int char) {
    if (peek != char) {
      throw new Exception('Expected: ${new String.fromCharCode(char)} found '
          '${new String.fromCharCode(peek)} at ${_index}');
    }
    consume();
  }

  void consume([int chars = 1]) {
    _index += chars;
  }

  bool isDone() => _index >= _runes.length;

  static bool isLetter(int char) =>
      (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A);

  static bool isNum(int char) => (char >= 0x30 && char <= 0x39);

  static bool isUpperCase(int char) => (char >= 0x41 && char <= 0x5A);

  static bool isLowerCase(int char) => (char >= 0x61 && char <= 0x7A);

  static bool isDartCase(int char) =>
      isNum(char) || isLetter(char) || char == $underscore;

  static bool isXmlCase(int char) =>
      isLetter(char) || isNum(char) || char == $dash || char == $underscore;
}

/// Node is the temporary AST structure.
///
/// All Fields are mutable for ease of use/performance.
/// toString acts as a desugar.
abstract class Node {
  String get name;
}

class Constructor extends Node {
  bool isElement;
  String name;
  List<Argument> arguments = [];
  List<Node> children = [];

  String toString() {
    String nested;
    if (children.isEmpty) {
      nested = '';
    } else if (children.length == 1 && children.first is Fragment) {
      nested = '${children.first}';
    } else {
      nested = '[' + children.reversed.map((x) => '$x').join(', ') + ']';
    }
    // TODO(jonahwilliams): special arguments for node?
    if (isElement) {
      return 'element(\'$name\')($nested)';
    }
    final args = arguments.map((x) => '$x').join(', ');
    return 'new $name($args)($nested)';
  }
}

class Argument extends Node {
  String name;
  String value;

  String toString() => '$name:$value';
}

class Fragment extends Node {
  String get name => 'fragment';
  String value;

  String toString() => value;
}

class Text extends Node {
  String get name => 'text';
  String value;

  String toString() => 'text($value)';
}
