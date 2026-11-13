import SwiftUI

/// Hand-cut outline of the review caption field (370×52) and the C13d card (370×88); stretches to any rect.
public struct FieldBlob: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.4069, 0.0006))
        path.addCurve(to: p(0.3315, 0.0083), control1: p(0.3768, 0.0006), control2: p(0.3543, 0.0037))
        path.addCurve(to: p(0.2698, 0.0300), control1: p(0.3085, 0.0130), control2: p(0.2948, 0.0269))
        path.addCurve(to: p(0.1832, 0.0254), control1: p(0.2452, 0.0316), control2: p(0.2114, 0.0238))
        path.addCurve(to: p(0.0996, 0.0347), control1: p(0.1547, 0.0254), control2: p(0.1191, 0.0285))
        path.addCurve(to: p(0.0664, 0.0563), control1: p(0.0801, 0.0393), control2: p(0.0741, 0.0486))
        path.addCurve(to: p(0.0533, 0.0780), control1: p(0.0587, 0.0625), control2: p(0.0571, 0.0702))
        path.addCurve(to: p(0.0426, 0.1058), control1: p(0.0491, 0.0873), control2: p(0.0475, 0.0873))
        path.addCurve(to: p(0.0231, 0.1894), control1: p(0.0376, 0.1244), control2: p(0.0283, 0.1631))
        path.addCurve(to: p(0.0113, 0.2714), control1: p(0.0179, 0.2173), control2: p(0.0146, 0.2389))
        path.addCurve(to: p(0.0031, 0.3859), control1: p(0.0080, 0.3039), control2: p(0.0047, 0.3411))
        path.addCurve(to: p(0.0001, 0.5360), control1: p(0.0012, 0.4293), control2: p(0.0003, 0.4927))
        path.addCurve(to: p(0.0014, 0.6506), control1: p(-0.0002, 0.5809), control2: p(0.0003, 0.6150))
        path.addCurve(to: p(0.0064, 0.7573), control1: p(0.0023, 0.6877), control2: p(0.0045, 0.7279))
        path.addCurve(to: p(0.0124, 0.8270), control1: p(0.0080, 0.7867), control2: p(0.0108, 0.8099))
        path.addCurve(to: p(0.0173, 0.8595), control1: p(0.0143, 0.8440), control2: p(0.0146, 0.8455))
        path.addCurve(to: p(0.0294, 0.9167), control1: p(0.0201, 0.8749), control2: p(0.0250, 0.9012))
        path.addCurve(to: p(0.0428, 0.9570), control1: p(0.0335, 0.9337), control2: p(0.0368, 0.9446))
        path.addCurve(to: p(0.0670, 0.9894), control1: p(0.0491, 0.9678), control2: p(0.0590, 0.9817))
        path.addCurve(to: p(0.0897, 0.9956), control1: p(0.0746, 0.9956), control2: p(0.0667, 0.9987))
        path.addCurve(to: p(0.2054, 0.9631), control1: p(0.1127, 0.9910), control2: p(0.1580, 0.9631))
        path.addCurve(to: p(0.3732, 0.9987), control1: p(0.2526, 0.9647), control2: p(0.3244, 0.9941))
        path.addCurve(to: p(0.4977, 0.9894), control1: p(0.4220, 1.0034), control2: p(0.4620, 0.9941))
        path.addCurve(to: p(0.5859, 0.9709), control1: p(0.5330, 0.9848), control2: p(0.5465, 0.9771))
        path.addCurve(to: p(0.7359, 0.9585), control1: p(0.6257, 0.9662), control2: p(0.6808, 0.9554))
        path.addCurve(to: p(0.9160, 0.9910), control1: p(0.7910, 0.9616), control2: p(0.8840, 0.9864))
        path.addCurve(to: p(0.9295, 0.9848), control1: p(0.9484, 0.9956), control2: p(0.9237, 0.9894))
        path.addCurve(to: p(0.9498, 0.9600), control1: p(0.9350, 0.9802), control2: p(0.9432, 0.9724))
        path.addCurve(to: p(0.9679, 0.9043), control1: p(0.9561, 0.9461), control2: p(0.9624, 0.9260))
        path.addCurve(to: p(0.9818, 0.8316), control1: p(0.9731, 0.8827), control2: p(0.9783, 0.8533))
        path.addCurve(to: p(0.9890, 0.7743), control1: p(0.9851, 0.8099), control2: p(0.9862, 0.8053))
        path.addCurve(to: p(0.9980, 0.6475), control1: p(0.9917, 0.7434), control2: p(0.9964, 0.6861))
        path.addCurve(to: p(0.9999, 0.5360), control1: p(0.9999, 0.6072), control2: p(0.9999, 0.5685))
        path.addCurve(to: p(0.9986, 0.4571), control1: p(0.9999, 0.5051), control2: p(1.0005, 0.4958))
        path.addCurve(to: p(0.9895, 0.3039), control1: p(0.9969, 0.4184), control2: p(0.9920, 0.3380))
        path.addCurve(to: p(0.9848, 0.2559), control1: p(0.9873, 0.2699), control2: p(0.9868, 0.2699))
        path.addCurve(to: p(0.9788, 0.2173), control1: p(0.9832, 0.2420), control2: p(0.9829, 0.2374))
        path.addCurve(to: p(0.9596, 0.1352), control1: p(0.9744, 0.1971), control2: p(0.9654, 0.1554))
        path.addCurve(to: p(0.9443, 0.0981), control1: p(0.9539, 0.1151), control2: p(0.9489, 0.1074))
        path.addCurve(to: p(0.9322, 0.0780), control1: p(0.9396, 0.0888), control2: p(0.9415, 0.0857))
        path.addCurve(to: p(0.8883, 0.0532), control1: p(0.9229, 0.0718), control2: p(0.9056, 0.0594))
        path.addCurve(to: p(0.8278, 0.0439), control1: p(0.8708, 0.0470), control2: p(0.8579, 0.0408))
        path.addCurve(to: p(0.7066, 0.0656), control1: p(0.7973, 0.0455), control2: p(0.7491, 0.0702))
        path.addCurve(to: p(0.5731, 0.0176), control1: p(0.6641, 0.0610), control2: p(0.5972, 0.0238))
        path.addCurve(to: p(0.5615, 0.0207), control1: p(0.5489, 0.0099), control2: p(0.5717, 0.0238))
        path.addCurve(to: p(0.5117, 0.0037), control1: p(0.5514, 0.0192), control2: p(0.5374, 0.0083))
        path.addCurve(to: p(0.4069, 0.0006), control1: p(0.4859, 0.0006), control2: p(0.4368, -0.0009))
        path.closeSubpath()
        return path
    }
}

/// Hand-cut outline of the review chips (Place, Voice note, Note; 98×34 in the design); stretches to any rect.
public struct ReviewChipBlob: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.2602, 0.0098))
        path.addCurve(to: p(0.1945, 0.0294), control1: p(0.1913, 0.0131), control2: p(0.2185, 0.0163))
        path.addCurve(to: p(0.1224, 0.0882), control1: p(0.1720, 0.0424), control2: p(0.1400, 0.0718))
        path.addCurve(to: p(0.0951, 0.1273), control1: p(0.1064, 0.1045), control2: p(0.1064, 0.1077))
        path.addCurve(to: p(0.0551, 0.2057), control1: p(0.0839, 0.1469), control2: p(0.0663, 0.1730))
        path.addCurve(to: p(0.0247, 0.3069), control1: p(0.0439, 0.2351), control2: p(0.0327, 0.2710))
        path.addCurve(to: p(0.0038, 0.4081), control1: p(0.0150, 0.3396), control2: p(0.0070, 0.3657))
        path.addCurve(to: p(0.0006, 0.5583), control1: p(0.0006, 0.4506), control2: p(-0.0010, 0.5093))
        path.addCurve(to: p(0.0150, 0.6987), control1: p(0.0022, 0.6073), control2: p(0.0054, 0.6530))
        path.addCurve(to: p(0.0535, 0.8228), control1: p(0.0231, 0.7412), control2: p(0.0407, 0.7869))
        path.addCurve(to: p(0.0935, 0.8946), control1: p(0.0679, 0.8554), control2: p(0.0807, 0.8783))
        path.addCurve(to: p(0.1304, 0.9371), control1: p(0.1064, 0.9142), control2: p(0.1160, 0.9240))
        path.addCurve(to: p(0.1865, 0.9730), control1: p(0.1464, 0.9501), control2: p(0.1688, 0.9632))
        path.addCurve(to: p(0.2345, 0.9893), control1: p(0.2041, 0.9828), control2: p(0.2041, 0.9828))
        path.addCurve(to: p(0.3739, 0.9991), control1: p(0.2666, 0.9926), control2: p(0.3307, 0.9991))
        path.addCurve(to: p(0.4925, 0.9958), control1: p(0.4172, 1.0024), control2: p(0.4684, 0.9958))
        path.addCurve(to: p(0.5229, 0.9828), control1: p(0.5181, 0.9926), control2: p(0.5069, 0.9828))
        path.addCurve(to: p(0.5838, 0.9991), control1: p(0.5373, 0.9828), control2: p(0.5501, 0.9958))
        path.addCurve(to: p(0.7232, 0.9958), control1: p(0.6174, 1.0024), control2: p(0.6895, 0.9958))
        path.addCurve(to: p(0.7856, 0.9926), control1: p(0.7568, 0.9926), control2: p(0.7680, 0.9958))
        path.addCurve(to: p(0.8209, 0.9762), control1: p(0.8017, 0.9893), control2: p(0.8065, 0.9860))
        path.addCurve(to: p(0.8721, 0.9338), control1: p(0.8353, 0.9664), control2: p(0.8561, 0.9534))
        path.addCurve(to: p(0.9186, 0.8620), control1: p(0.8882, 0.9142), control2: p(0.9058, 0.8848))
        path.addCurve(to: p(0.9490, 0.7967), control1: p(0.9314, 0.8391), control2: p(0.9410, 0.8162))
        path.addCurve(to: p(0.9651, 0.7444), control1: p(0.9571, 0.7771), control2: p(0.9587, 0.7738))
        path.addCurve(to: p(0.9939, 0.6040), control1: p(0.9731, 0.7118), control2: p(0.9891, 0.6497))
        path.addCurve(to: p(0.9987, 0.4767), control1: p(0.9987, 0.5583), control2: p(1.0019, 0.5257))
        path.addCurve(to: p(0.9779, 0.3134), control1: p(0.9955, 0.4277), control2: p(0.9843, 0.3559))
        path.addCurve(to: p(0.9555, 0.2318), control1: p(0.9699, 0.2710), control2: p(0.9619, 0.2514))
        path.addCurve(to: p(0.9378, 0.1894), control1: p(0.9490, 0.2122), control2: p(0.9458, 0.2057))
        path.addCurve(to: p(0.9058, 0.1273), control1: p(0.9298, 0.1730), control2: p(0.9186, 0.1502))
        path.addCurve(to: p(0.8593, 0.0686), control1: p(0.8930, 0.1077), control2: p(0.8705, 0.0816))
        path.addCurve(to: p(0.8353, 0.0490), control1: p(0.8481, 0.0555), control2: p(0.8545, 0.0588))
        path.addCurve(to: p(0.7488, 0.0098), control1: p(0.8177, 0.0392), control2: p(0.7856, 0.0163))
        path.addCurve(to: p(0.6126, 0.0000), control1: p(0.7119, 0.0000), control2: p(0.6943, 0.0000))
        path.addCurve(to: p(0.2602, 0.0098), control1: p(0.5309, 0.0000), control2: p(0.3290, 0.0033))
        path.closeSubpath()
        return path
    }
}
