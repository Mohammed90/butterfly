import 'package:butterfly/butterfly.dart';

class Dx implements Node {
  Dx(String _);

  @override
  Key get key => null;

  @override
  instantiate(_) {}
}

class FooWidget extends StatelessWidget {
  @override
  Node build() {
    var local = false;
    return div()([text("Some Text"),input(checked: local)()]);
  }
}