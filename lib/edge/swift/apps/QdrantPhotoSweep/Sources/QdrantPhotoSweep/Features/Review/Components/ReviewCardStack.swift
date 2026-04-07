import SwiftUI

struct ReviewCardStack: View {
    let group: DuplicateGroup?
    let keptIds: Set<String>
    @Binding var dragOffset: CGFloat
    @Binding var fullscreenPhoto: PhotoReference?
    let onToggleKeep: (PhotoReference) -> Void
    let onSwipedOut: () -> Void

    private var swipeOpacity: Double {
        let progress = abs(dragOffset) / 200
        return Double(1 - progress * 0.3)
    }

    private var isDragging: Bool {
        dragOffset != 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let group {
                    GroupComparisonView(
                        group: group,
                        keptIds: keptIds,
                        onToggleKeep: onToggleKeep,
                        onFullscreen: { photo in
                            fullscreenPhoto = photo
                        }
                    )
                    .id(group.id)
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) / 30), anchor: .bottom)
                    .opacity(swipeOpacity)
                    .allowsHitTesting(!isDragging)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(swipeGesture(screenWidth: geo.size.width))
                    .allowsHitTesting(isDragging)
            }
            .simultaneousGesture(swipeDetectionGesture(screenWidth: geo.size.width))
            .animation(QAnimation.springDefault, value: group?.id)
        }
    }

    // MARK: - Gestures

    private func swipeDetectionGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard dragOffset != 0 else { return }
                evaluateSwipe(translation: value.translation.width, velocity: value.predictedEndTranslation.width, screenWidth: screenWidth)
            }
    }

    private func swipeGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                evaluateSwipe(translation: value.translation.width, velocity: value.predictedEndTranslation.width, screenWidth: screenWidth)
            }
    }

    private func evaluateSwipe(translation: CGFloat, velocity: CGFloat, screenWidth: CGFloat) {
        let swipeThreshold = screenWidth * 0.3

        switch true {
        case translation < -swipeThreshold || velocity < -500:
            performSwipeOut(direction: .left, screenWidth: screenWidth)
        case translation > swipeThreshold || velocity > 500:
            performSwipeOut(direction: .right, screenWidth: screenWidth)
        default:
            withAnimation(QAnimation.springDefault) {
                dragOffset = 0
            }
        }
    }

    private func performSwipeOut(direction: SwipeDirection, screenWidth: CGFloat) {
        let exitX: CGFloat = direction == .left ? -screenWidth * 1.5 : screenWidth * 1.5

        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = exitX
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = 0
            onSwipedOut()
        }
    }
}

enum SwipeDirection {
    case none, left, right
}
