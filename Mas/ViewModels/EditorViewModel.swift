import SwiftUI
import AppKit

@MainActor
class EditorViewModel: ObservableObject {
    @Published var screenshot: Screenshot
    @Published var selectedTool: AnnotationType = .arrow
    @Published var selectedColor: NSColor = .systemRed
    @Published var lineWidth: CGFloat = 3
    @Published var fontSize: CGFloat = 16
    @Published var textInput: String = ""
    @Published var isEditingText: Bool = false
    @Published var currentTextAnnotation: TextAnnotation?

    private var undoStack: [[any Annotation]] = []
    private var redoStack: [[any Annotation]] = []

    private let fileStorageService = FileStorageService()
    private let clipboardService = ClipboardService()

    init(screenshot: Screenshot) {
        self.screenshot = screenshot
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func addAnnotation(_ annotation: any Annotation) {
        saveStateForUndo()
        screenshot.annotations.append(annotation)
        redoStack.removeAll()
    }

    func removeAnnotation(at index: Int) {
        guard index < screenshot.annotations.count else { return }
        saveStateForUndo()
        screenshot.annotations.remove(at: index)
        redoStack.removeAll()
    }

    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(screenshot.annotations)
        screenshot.annotations = previousState
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(screenshot.annotations)
        screenshot.annotations = nextState
    }

    private func saveStateForUndo() {
        undoStack.append(screenshot.annotations)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    func createAnnotation(from startPoint: CGPoint, to endPoint: CGPoint) -> (any Annotation)? {
        switch selectedTool {
        case .arrow:
            return ArrowAnnotation(startPoint: startPoint, endPoint: endPoint, color: selectedColor, lineWidth: lineWidth)
        case .rectangle:
            let rect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
            return RectAnnotation(rect: rect, color: selectedColor, lineWidth: lineWidth)
        case .highlight:
            let rect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
            return HighlightAnnotation(rect: rect, color: selectedColor)
        case .mosaic:
            let rect = CGRect(
                x: min(startPoint.x, endPoint.x),
                y: min(startPoint.y, endPoint.y),
                width: abs(endPoint.x - startPoint.x),
                height: abs(endPoint.y - startPoint.y)
            )
            return MosaicAnnotation(rect: rect)
        case .text:
            return nil
        }
    }

    func startTextAnnotation(at point: CGPoint) {
        let annotation = TextAnnotation(
            position: point,
            text: "",
            font: .systemFont(ofSize: fontSize, weight: .medium),
            color: selectedColor
        )
        currentTextAnnotation = annotation
        isEditingText = true
        textInput = ""
    }

    func finishTextAnnotation() {
        guard let annotation = currentTextAnnotation, !textInput.isEmpty else {
            currentTextAnnotation = nil
            isEditingText = false
            textInput = ""
            return
        }

        annotation.text = textInput
        addAnnotation(annotation)
        currentTextAnnotation = nil
        isEditingText = false
        textInput = ""
    }

    @MainActor
    func saveImage(format: FileStorageService.ImageFormat = .png) async -> URL? {
        let finalImage = screenshot.renderFinalImage()
        return await fileStorageService.saveImage(finalImage, format: format)
    }

    func saveToDesktop(format: FileStorageService.ImageFormat = .png) throws -> URL {
        let finalImage = screenshot.renderFinalImage()
        return try fileStorageService.saveImageToDefaultLocation(finalImage, format: format)
    }

    func copyToClipboard() -> Bool {
        let finalImage = screenshot.renderFinalImage()
        return clipboardService.copyToClipboard(finalImage)
    }
}
