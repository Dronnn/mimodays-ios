@testable import AppFeature
import CoreGraphics
import Persistence
import Testing

/// B.3: one layout for the Memory Card, the editor preview and the exported movie.
struct MomentCompositionTests {
    /// The camera's frames today: a 3:4 rear picture and a 3:4 selfie.
    private let main = CGSize(width: 1440, height: 1920)
    private let selfie = CGSize(width: 1080, height: 1440)

    private func input(_ format: CaptureFormat, _ layout: ClipCameraLayout = .window, window: PiPLayout? = nil, selfie: CGSize? = nil) -> MomentComposition.Input {
        MomentComposition.Input(main: main, selfie: selfie ?? self.selfie, format: format, layout: layout, window: window)
    }

    private func card(_ format: CaptureFormat) -> CGSize {
        CGSize(width: 402, height: 402 / format.aspectRatio)
    }

    private func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 0.0001) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    private func share(_ rect: CGRect, of canvas: CGSize) -> CGRect {
        CGRect(x: rect.minX / canvas.width, y: rect.minY / canvas.height, width: rect.width / canvas.width, height: rect.height / canvas.height)
    }

    @Test func eachFormatCropsTheMiddleOfTheFrame() {
        #expect(close(MomentComposition.crop(main, to: 9.0 / 16), CGRect(x: 0.125, y: 0, width: 0.75, height: 1)))
        #expect(close(MomentComposition.crop(main, to: 1), CGRect(x: 0, y: 0.125, width: 1, height: 0.75)))
        #expect(close(MomentComposition.crop(CGSize(width: 1920, height: 1440), to: 16.0 / 9), CGRect(x: 0, y: 0.125, width: 1, height: 0.75)))
        #expect(MomentComposition.crop(.zero, to: 1) == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func onItsCardTheWindowIsWhereItWasPut() throws {
        let canvas = card(.portrait)
        let layout = PiPLayout(centerX: 0.75, centerY: 0.2, scale: 0.3)
        let composition = MomentComposition(input(.portrait, window: layout), canvas: canvas)
        #expect(composition.pictures.count == 1)
        #expect(composition.pictures[0].stream == .main)
        #expect(close(composition.pictures[0].frame, CGRect(origin: .zero, size: canvas)))
        let window = try #require(composition.window)
        #expect(window.stream == .selfie && window.rotation == -5.4)
        #expect(abs(window.frame.midX - 0.75 * canvas.width) < 0.001 && abs(window.frame.midY - 0.2 * canvas.height) < 0.001)
        #expect(abs(window.frame.width - 0.3 * 402) < 0.001)
        #expect(abs(window.frame.height / window.frame.width - 150.0 / 112) < 0.001)
        // The selfie fills its window without stretching.
        #expect(abs(window.crop.width * selfie.width / (window.crop.height * selfie.height) - window.frame.width / window.frame.height) < 0.001)
    }

    @Test func withoutASavedWindowItStartsWhereTheCameraPutsIt() throws {
        let window = try #require(MomentComposition(input(.portrait), canvas: card(.portrait)).window)
        #expect(abs(window.frame.maxX - (402 - 23.3)) < 0.001)
        #expect(abs(window.frame.minY - 49.1) < 0.001)
        #expect(abs(window.frame.width - 112) < 0.001 && abs(window.frame.height - 150) < 0.001)
    }

    @Test func aLandscapeWindowLiesOnItsSideAtTheSameSize() throws {
        let window = try #require(MomentComposition(input(.landscape, window: PiPLayout(centerX: 0.8, centerY: 0.3, scale: 112.0 / 402)), canvas: card(.landscape)).window)
        #expect(abs(window.frame.height - 112.0 / 402 * card(.landscape).height) < 0.001)
        #expect(abs(window.frame.width / window.frame.height - 150.0 / 112) < 0.001)
    }

    @Test func swappingPutsTheMainStreamInTheWindow() throws {
        let composition = MomentComposition(input(.square, .swapped, window: PiPLayout(centerX: 0.2, centerY: 0.2, scale: 0.3)), canvas: card(.square))
        #expect(composition.pictures.map(\.stream) == [.selfie])
        #expect(try #require(composition.window).stream == .main)
        #expect(close(composition.pictures[0].crop, MomentComposition.crop(selfie, to: 1)))
    }

    @Test func oneStreamAloneHasNoWindow() {
        let main = MomentComposition(input(.portrait, .mainOnly), canvas: card(.portrait))
        #expect(main.pictures.map(\.stream) == [.main] && main.window == nil)
        let selfie = MomentComposition(input(.portrait, .selfieOnly), canvas: card(.portrait))
        #expect(selfie.pictures.map(\.stream) == [.selfie] && selfie.window == nil)
    }

    @Test func sideBySideStacksOnPortraitAndSquareAndSitsNextToEachOtherOnLandscape() {
        for format in CaptureFormat.allCases {
            let canvas = card(format)
            let composition = MomentComposition(input(format, .sideBySide), canvas: canvas)
            #expect(composition.window == nil)
            #expect(composition.pictures.map(\.stream) == [.main, .selfie])
            let (first, second) = (composition.pictures[0].frame, composition.pictures[1].frame)
            #expect(close(first.union(second), CGRect(origin: .zero, size: canvas), 0.001))
            if format == .landscape {
                #expect(first.maxX <= second.minX + 0.001 && first.height == canvas.height)
            } else {
                #expect(first.maxY <= second.minY + 0.001 && first.width == canvas.width)
            }
            // Each half is filled without stretching.
            for picture in composition.pictures {
                let source = picture.stream == .main ? main : selfie
                #expect(abs(picture.crop.width * source.width / (picture.crop.height * source.height) - picture.frame.width / picture.frame.height) < 0.001)
            }
        }
    }

    @Test func oneCameraIsAlwaysTheMainPictureAlone() {
        for layout in ClipCameraLayout.allCases {
            let composition = MomentComposition(MomentComposition.Input(main: main, selfie: nil, format: .portrait, layout: layout), canvas: card(.portrait))
            #expect(composition.pictures.map(\.stream) == [.main] && composition.window == nil)
        }
    }

    @Test func aWindowPutPastTheEdgeStaysInside() throws {
        let canvas = card(.portrait)
        let window = try #require(MomentComposition(input(.portrait, window: PiPLayout(centerX: 1.1, centerY: -0.2, scale: 0.3)), canvas: canvas).window)
        #expect(window.frame.minY == 0 && abs(window.frame.maxX - canvas.width) < 0.001)
    }

    @Test func inAMovieOfAnotherShapeFillCoversAndShowAllFits() {
        let movie = CGSize(width: 1080, height: 1920)
        let fill = MomentComposition(input(.landscape, .mainOnly), canvas: movie, fit: .fill).pictures[0].frame
        #expect(abs(fill.height - 1920) < 0.001 && fill.width > 1080 && abs(fill.midX - 540) < 0.001)
        let showAll = MomentComposition(input(.landscape, .mainOnly), canvas: movie, fit: .showAll).pictures[0].frame
        #expect(abs(showAll.width - 1080) < 0.001 && abs(showAll.height - 1080 * 9 / 16) < 0.001 && abs(showAll.midY - 960) < 0.001)
    }

    /// Preview = export: the editor preview and every exported resolution lay out the same picture, scaled.
    @Test func thePreviewAndEveryExportAgreeForEveryFormatAndLayout() {
        let window = PiPLayout(centerX: 0.3, centerY: 0.7, scale: 0.25)
        for movie in MovieAspectRatio.allCases {
            let preview = CGSize(width: 370, height: 370 / (movie.renderSize(.p720).width / movie.renderSize(.p720).height))
            for format in CaptureFormat.allCases {
                for layout in ClipCameraLayout.allCases {
                    for fit in [MovieFit.fill, .showAll] {
                        let shown = MomentComposition(input(format, layout, window: window), canvas: preview, fit: fit)
                        for resolution in MovieResolution.allCases {
                            let size = movie.renderSize(resolution)
                            let exported = MomentComposition(input(format, layout, window: window), canvas: size, fit: fit)
                            #expect(shown.pictures.count == exported.pictures.count)
                            for (a, b) in zip(shown.pictures, exported.pictures) {
                                #expect(a.stream == b.stream && close(a.crop, b.crop))
                                #expect(close(share(a.frame, of: preview), share(b.frame, of: size), 0.001))
                            }
                            #expect((shown.window == nil) == (exported.window == nil))
                            if let a = shown.window, let b = exported.window {
                                #expect(a.stream == b.stream && a.rotation == b.rotation && close(a.crop, b.crop))
                                #expect(close(share(a.frame, of: preview), share(b.frame, of: size), 0.001))
                            }
                        }
                    }
                }
            }
        }
    }
}
