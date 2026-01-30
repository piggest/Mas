import SwiftUI
import AppKit

struct CanvasView: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(viewModel: viewModel)
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.viewModel = viewModel
        nsView.needsDisplay = true
    }
}

class CanvasNSView: NSView {
    var viewModel: EditorViewModel
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isDrawing = false
    private var textField: NSTextField?

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let image = viewModel.screenshot.originalImage
        let imageRect = CGRect(origin: .zero, size: image.size)
        image.draw(in: imageRect)

        for annotation in viewModel.screenshot.annotations {
            annotation.draw(in: imageRect)
        }

        if isDrawing, let start = startPoint, let current = currentPoint {
            drawPreview(from: start, to: current, context: context)
        }

        if viewModel.isEditingText, let annotation = viewModel.currentTextAnnotation {
            drawTextCursor(at: annotation.position)
        }
    }

    private func drawPreview(from start: CGPoint, to current: CGPoint, context: CGContext) {
        switch viewModel.selectedTool {
        case .arrow:
            let arrow = ArrowAnnotation(startPoint: start, endPoint: current, color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            arrow.draw(in: bounds)

        case .rectangle:
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let rectAnnotation = RectAnnotation(rect: rect, color: viewModel.selectedColor, lineWidth: viewModel.lineWidth)
            rectAnnotation.draw(in: bounds)

        case .highlight:
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let highlight = HighlightAnnotation(rect: rect, color: viewModel.selectedColor)
            highlight.draw(in: bounds)

        case .mosaic:
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            let mosaic = MosaicAnnotation(rect: rect)
            mosaic.draw(in: bounds)

        case .text:
            break
        }
    }

    private func drawTextCursor(at point: CGPoint) {
        NSColor.systemBlue.setStroke()
        let cursorPath = NSBezierPath()
        cursorPath.move(to: CGPoint(x: point.x, y: point.y))
        cursorPath.line(to: CGPoint(x: point.x, y: point.y + viewModel.fontSize))
        cursorPath.lineWidth = 2
        cursorPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let flippedPoint = CGPoint(x: point.x, y: bounds.height - point.y)

        if viewModel.selectedTool == .text {
            if viewModel.isEditingText {
                viewModel.finishTextAnnotation()
                removeTextField()
            }
            showTextField(at: flippedPoint)
        } else {
            startPoint = flippedPoint
            currentPoint = flippedPoint
            isDrawing = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = CGPoint(x: point.x, y: bounds.height - point.y)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDrawing, let start = startPoint, let current = currentPoint else { return }

        if let annotation = viewModel.createAnnotation(from: start, to: current) {
            viewModel.addAnnotation(annotation)
        }

        startPoint = nil
        currentPoint = nil
        isDrawing = false
        needsDisplay = true
    }

    private func showTextField(at point: CGPoint) {
        viewModel.startTextAnnotation(at: point)

        let displayPoint = CGPoint(x: point.x, y: bounds.height - point.y - viewModel.fontSize)

        let field = NSTextField(frame: NSRect(x: displayPoint.x, y: displayPoint.y, width: 200, height: viewModel.fontSize + 8))
        field.isBordered = true
        field.backgroundColor = .white
        field.font = .systemFont(ofSize: viewModel.fontSize, weight: .medium)
        field.textColor = viewModel.selectedColor
        field.focusRingType = .none
        field.target = self
        field.action = #selector(textFieldDidEndEditing)
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    private func removeTextField() {
        textField?.removeFromSuperview()
        textField = nil
    }

    @objc private func textFieldDidEndEditing() {
        viewModel.textInput = textField?.stringValue ?? ""
        viewModel.finishTextAnnotation()
        removeTextField()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if viewModel.isEditingText {
                viewModel.isEditingText = false
                viewModel.currentTextAnnotation = nil
                removeTextField()
            }
            isDrawing = false
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }
}

extension CanvasNSView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        viewModel.textInput = textField?.stringValue ?? ""
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        textFieldDidEndEditing()
    }
}
