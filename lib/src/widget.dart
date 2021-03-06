// Copyright 2016 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

part of butterfly;

/// A kind of node that's composed of other nodes.
abstract class Widget extends Node {
  const Widget({Key key}) : super(key: key);
}

/// A widget built out of other [Node]s and has no mutable state.
///
/// As a matter of good practice prefer making stateless widgets immutable, or
/// even better, support `const`. Because mutations on a stateless widget do not
/// make sense, immutabity sets the right expectation that the state cannot be
/// altered.
abstract class StatelessWidget extends Widget {
  const StatelessWidget({Key key}) : super(key: key);

  RenderNode instantiate(Tree t) => new RenderStatelessWidget(t, this);

  Node build();
}

/// A widget that's built from a mutable [State] object.
///
/// As a matter of good practice, prefer making the widget class immutable, or
/// even better, support `const`. However, the [State] object can be mutable. In
/// fact, it should be mutable. If you find that the state object is immutable,
/// consider switching to a [StatelessWidget].
abstract class StatefulWidget extends Widget {
  const StatefulWidget({Key key}) : super(key: key);

  State createState();

  RenderNode instantiate(Tree t) => new RenderStatefulWidget(t, this);
}

/// Mutable state of a [StatefulWidget].
abstract class State<T extends StatefulWidget> {
  RenderStatefulWidget _node;
  T _config;
  T get config => _config;

  Node build();

  void scheduleUpdate() {
    _node.scheduleUpdate();
  }
}

// TODO: this begs for a better API
void internalSetStateNode(State state, RenderStatefulWidget node) {
  state._node = node;
}

class RenderStatelessWidget extends RenderParent<StatelessWidget> {
  RenderStatelessWidget(Tree tree, StatelessWidget configuration)
      : super(tree, configuration);

  RenderNode _child;

  @override
  void visitChildren(void visitor(RenderNode child)) {
    visitor(_child);
  }

  @override
  void replaceChildNativeNode(html.Node oldNode, html.Node replacement) {
    parent.replaceChildNativeNode(oldNode, replacement);
  }

  html.Node get nativeNode => _child.nativeNode;

  @override
  void update(StatelessWidget newConfiguration) {
    assert(newConfiguration != null);
    if (!identical(configuration, newConfiguration)) {
      // Build the new configuration and decide whether to reuse the child node
      // or replace with a new one.
      Node newChildConfiguration = newConfiguration.build();
      if (_child != null && _canUpdate(_child, newChildConfiguration)) {
        _child.update(newChildConfiguration);
      } else {
        // Replace child
        _child?.detach();
        _child = newChildConfiguration.instantiate(tree);
        _child.attach(this);
      }
    } else if (hasDescendantsNeedingUpdate) {
      // Own configuration is the same, but some children are scheduled to be
      // updated.
      _child.update(_child.configuration);
    }
    super.update(newConfiguration);
  }
}

class RenderStatefulWidget extends RenderParent<StatefulWidget> {
  RenderStatefulWidget(Tree tree, StatefulWidget configuration)
      : super(tree, configuration);

  State _state;
  State get state => _state;
  RenderNode _child;
  bool _isDirty = false;

  @override
  void visitChildren(void visitor(RenderNode child)) {
    visitor(_child);
  }

  @override
  void replaceChildNativeNode(html.Node oldNode, html.Node replacement) {
    parent.replaceChildNativeNode(oldNode, replacement);
  }

  html.Node get nativeNode => _child.nativeNode;

  void scheduleUpdate() {
    _isDirty = true;
    super.scheduleUpdate();
  }

  void update(StatefulWidget newConfiguration) {
    assert(newConfiguration != null);
    if (!identical(configuration, newConfiguration)) {
      // Build the new configuration and decide whether to reuse the child node
      // or replace with a new one.
      _state = newConfiguration.createState();
      _state._config = newConfiguration;
      internalSetStateNode(_state, this);
      Node newChildConfiguration = _state.build();
      if (_child != null && identical(newChildConfiguration.runtimeType, _child.configuration.runtimeType)) {
        _child.update(newChildConfiguration);
      } else {
        _child?.detach();
        _child = newChildConfiguration.instantiate(tree);
        _child.attach(this);
      }
    } else if (_isDirty) {
      _child.update(_state.build());
    } else if (hasDescendantsNeedingUpdate) {
      // Own configuration is the same, but some children are scheduled to be
      // updated.
      _child.update(_child.configuration);
    }

    _isDirty = false;
    super.update(newConfiguration);
  }
}
