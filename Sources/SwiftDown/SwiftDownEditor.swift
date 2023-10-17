//
//  File.swift
//
//
//  Created by Quentin Eude on 16/03/2021.
//

import Down
import SwiftUI
import Combine

#if os(iOS)
  // MARK: - SwiftDownEditor iOS
public struct SwiftDownEditor: UIViewRepresentable {
  private var debounceTime = 0.3
  private var styleUpdateCue = PassthroughSubject<Any, Never>()
  @Binding var text: String {
    didSet {
      onTextChange(text)
    }
  }

    @Binding var selectedRange: (NSRange, MarkdownNode?)

    private(set) var isEditable: Bool = true
    private(set) var theme: Theme = Theme.BuiltIn.defaultDark.theme()
    private(set) var insetsSize: CGFloat = 0
    private(set) var autocapitalizationType: UITextAutocapitalizationType = .sentences
    private(set) var autocorrectionType: UITextAutocorrectionType = .default
    private(set) var keyboardType: UIKeyboardType = .default
    private(set) var textAlignment: TextAlignment = .leading

    public var onTextChange: (String) -> Void = { _ in }
    let engine = MarkdownEngine()

    public init(
      text: Binding<String>,
      onTextChange: @escaping (String) -> Void = { _ in }
    ) {
      _text = text
      _selectedRange = .constant((NSRange(), nil))
      self.onTextChange = onTextChange
    }

    public init(
      text: Binding<String>,
      selectedRange: Binding<(NSRange, MarkdownNode?)>,
      onTextChange: @escaping (String) -> Void = { _ in }
    ) {
      _text = text
      _selectedRange = selectedRange
      self.onTextChange = onTextChange
    }

    public func makeUIView(context: Context) -> SwiftDown {
      let swiftDown = SwiftDown(frame: .zero, theme: theme)
      swiftDown.storage.markdowner = { self.engine.render($0, offset: $1) }
      swiftDown.storage.applyMarkdown = { m in Theme.applyMarkdown(markdown: m, with: self.theme) }
      swiftDown.storage.applyBody = { Theme.applyBody(with: self.theme) }
      swiftDown.swiftDownDelegate = context.coordinator
      swiftDown.isEditable = true
      swiftDown.isScrollEnabled = true
      swiftDown.keyboardType = keyboardType
      swiftDown.autocapitalizationType = autocapitalizationType
      swiftDown.autocorrectionType = autocorrectionType
      swiftDown.textContainerInset = UIEdgeInsets(
        top: insetsSize, left: insetsSize, bottom: insetsSize, right: insetsSize)
      swiftDown.backgroundColor = theme.backgroundColor
      swiftDown.tintColor = theme.tintColor
      swiftDown.textColor = theme.tintColor
      swiftDown.text = text

      context.coordinator.cancellable = styleUpdateCue.debounce(for: .seconds(debounceTime), scheduler: RunLoop.main).sink { _ in
        let selectedRanges = swiftDown.selectedRange
        swiftDown.text = text
        swiftDown.highlighter?.applyStyles()
        swiftDown.selectedRange = selectedRanges
      }
      return swiftDown
    }

    public func updateUIView(_ uiView: SwiftDown, context: Context) {
      styleUpdateCue.send(0)
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }
  }

  // MARK: - SwiftDownEditor iOS Coordinator
  extension SwiftDownEditor {
      public class Coordinator: NSObject, SwiftDownDelegate {
      public var cancellable: Cancellable?

      var parent: SwiftDownEditor

      init(_ parent: SwiftDownEditor) {
        self.parent = parent
      }

      public func textViewDidChange(_ textView: SwiftDown) {
        guard textView.markedTextRange == nil else { return }

        DispatchQueue.main.async {
          self.parent.text = textView.text
        }
      }

      public func textViewDidChangeSelection(_ textView: SwiftDown) {
        guard textView.markedTextRange == nil else { return }

        let rng = textView.selectedRange
        DispatchQueue.main.async {
          self.parent.selectedRange = (
            rng,
            tryFindingMarkdownNode(rng: rng, markdownNodes: textView.storage.markdownNodes)
          )
        }
      }
    }
  }

  // MARK: - iOS Specifics modifiers
  extension SwiftDownEditor {
    public func autocapitalizationType(_ type: UITextAutocapitalizationType) -> Self {
      var new = self
      new.autocapitalizationType = type
      return new
    }

    public func autocorrectionType(_ type: UITextAutocorrectionType) -> Self {
      var new = self
      new.autocorrectionType = type
      return new
    }

    public func keyboardType(_ type: UIKeyboardType) -> Self {
      var new = self
      new.keyboardType = type
      return new
    }

    public func textAlignment(_ type: TextAlignment) -> Self {
      var new = self
      new.textAlignment = type
      return new
    }
  }
#else
  // MARK: - SwiftDownEditor macOS
  public struct SwiftDownEditor: NSViewRepresentable {
    private var debounceTime = 0.3
    private var styleUpdateCue = PassthroughSubject<Any, Never>()
    @Binding var text: String {
      didSet {
        onTextChange(text)
      }
    }

    @Binding var selectedRange: (NSRange, MarkdownNode?)

    private(set) var isEditable: Bool = true
    private(set) var theme: Theme = Theme.BuiltIn.defaultDark.theme()
    private(set) var insetsSize: CGFloat = 0

    public var onTextChange: (String) -> Void = { _ in }

    public init(
      text: Binding<String>,
      onTextChange: @escaping (String) -> Void = { _ in }
    ) {
      _text = text
      _selectedRange = .constant((NSRange(), nil))
      self.onTextChange = onTextChange
    }

    public init(
      text: Binding<String>,
      selectedRange: Binding<(NSRange, MarkdownNode?)>,
      onTextChange: @escaping (String) -> Void = { _ in }
    ) {
      _text = text
      _selectedRange = selectedRange
      self.onTextChange = onTextChange
    }

    public func makeNSView(context: Context) -> SwiftDown {
      let swiftDown = SwiftDown(theme: theme, isEditable: isEditable, insetsSize: insetsSize)
      swiftDown.delegate = context.coordinator
      swiftDown.setupTextView()
      swiftDown.text = text

      context.coordinator.cancellable = styleUpdateCue
        .debounce(for: .seconds(debounceTime), scheduler: RunLoop.main)
        .sink { _ in
          let selectedRanges = swiftDown.selectedRanges
          swiftDown.text = text
          swiftDown.applyStyles()
          swiftDown.selectedRanges = selectedRanges
        }
      return swiftDown
    }

    public func updateNSView(_ nsView: SwiftDown, context: Context) {
      styleUpdateCue.send(0)
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }
  }

  // MARK: - SwiftDownEditor Coordinator macOS
  extension SwiftDownEditor {
    // MARK: - Coordinator
    public class Coordinator: NSObject, NSTextViewDelegate {
      var cancellable: Cancellable?
      var parent: SwiftDownEditor
      init(_ parent: SwiftDownEditor) {
        self.parent = parent
      }

      public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
          return
        }

        self.parent.text = textView.string
      }

      public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
          return
        }
        let rng = textView.selectedRange()
        if let c = textView as? CustomTextView {
          DispatchQueue.main.async {
            self.parent.selectedRange = (rng, tryFindingMarkdownNode(rng: rng, markdownNodes: c.storage.markdownNodes))
          }
        }
      }
    }
  }
#endif

// MARK: - Common Modifiers
extension SwiftDownEditor {
  public func insetsSize(_ size: CGFloat) -> Self {
    var editor = self
    editor.insetsSize = size
    return editor
  }

  public func theme(_ theme: Theme) -> Self {
    var editor = self
    editor.theme = theme
    return editor
  }

  public func isEditable(_ isEditable: Bool) -> Self {
    var editor = self
    editor.isEditable = isEditable
    return editor
  }

  public func debounceTime(_ debounceTime: Double) -> Self {
    var editor = self
    editor.debounceTime = debounceTime
    return editor
  }
}

func isBiggerThan(x: NSRange, y:NSRange) -> Bool {
  return x.location <= y.location && y.location + y.length <= x.location + x.length
}

func tryFindingMarkdownNode(rng: NSRange, markdownNodes: [MarkdownNode]) -> MarkdownNode? {
    markdownNodes.reduce(nil) { prev, mn in
      if isBiggerThan(x: mn.range, y: rng) {
        if let prev = prev {
          if isBiggerThan(x: prev.range, y: mn.range) {
            return mn
          } else {
            return prev
          }
        } else {
          return mn
        }
      } else {
        return prev
      }
    }
}
