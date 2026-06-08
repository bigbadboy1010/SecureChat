// SecureChat/BIT/Views/IntroView.swift

import SwiftUI


private struct BITLogoMark: View {
    var body: some View {
        VStack(spacing: 6) {
            // ASCII-style mark (monospace)
            Text("""
██████╗ ██╗████████╗
██╔══██╗██║╚══██╔══╝
██████╔╝██║   ██║
██╔══██╗██║   ██║
██████╔╝██║   ██║
╚═════╝ ╚═╝   ╚═╝
""")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.green.opacity(0.7))
            .multilineTextAlignment(.center)
            .lineSpacing(2)

            // Simple vector-ish circuit lines
            CircuitLines()
                .frame(height: 46)
                .opacity(0.55)
        }
    }
}

private struct CircuitLines: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.5))
                p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.2))
                p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.2))
                p.addLine(to: CGPoint(x: w * 0.7, y: h * 0.5))
                p.addLine(to: CGPoint(x: w, y: h * 0.5))

                p.move(to: CGPoint(x: w * 0.35, y: h * 0.5))
                p.addEllipse(in: CGRect(x: w * 0.33, y: h * 0.48, width: 6, height: 6))

                p.move(to: CGPoint(x: w * 0.7, y: h * 0.5))
                p.addEllipse(in: CGRect(x: w * 0.68, y: h * 0.48, width: 6, height: 6))

                p.move(to: CGPoint(x: w * 0.62, y: h * 0.2))
                p.addEllipse(in: CGRect(x: w * 0.60, y: h * 0.18, width: 6, height: 6))
            }
            .stroke(Color.green, lineWidth: 1)
        }
    }
}

struct IntroView: View {
    @State private var glow: Double = 0.2
    @State private var flicker: Double = 1.0
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.02, green: 0.08, blue: 0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            MatrixRain()
                .opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                BITLogoMark()
                    .padding(.bottom, 6)

                Text("BIT")
                    .font(.system(size: 64, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.9))
                    .shadow(color: Color.green.opacity(glow), radius: 18, x: 0, y: 0)
                    .opacity(flicker)

                Text("SecureChat")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.85))
                    .shadow(color: Color.green.opacity(glow * 0.8), radius: 10, x: 0, y: 0)

                Text("E2E · Double Ratchet · Sender Keys")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.65))

                Spacer().frame(height: 12)

                Button {
                    onFinish()
                } label: {
                    Text("Start")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.55), lineWidth: 1)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.green.opacity(0.9))
                .padding(.top, 6)
            }
            .padding(.top, 80)
            .padding(.bottom, 60)
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glow = 0.85
            }
            withAnimation(.linear(duration: 0.12).repeatForever(autoreverses: true)) {
                flicker = 0.92
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                onFinish()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BIT SecureChat Intro")
    }
}

// MARK: - Matrix background

private struct MatrixRain: View {
    @State private var phase: CGFloat = 0
    private let columns = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { i in
                    ColumnRain(seed: i, height: h)
                        .frame(width: w / CGFloat(columns))
                }
            }
            .offset(y: phase)
            .onAppear {
                withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                    phase = -h
                }
            }
        }
        
    }
}

private struct ColumnRain: View {
    let seed: Int
    let height: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<28, id: \.self) { j in
                Text(randomGlyph(i: seed, j: j))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(opacity(j: j)))
            }
        }
        .padding(.top, CGFloat((seed * 17) % 120))
    }

    private func randomGlyph(i: Int, j: Int) -> String {
        let glyphs = Array("01#@*+|:.")
        let idx = (i * 31 + j * 7) % glyphs.count
        return String(glyphs[idx])
    }

    private func opacity(j: Int) -> Double {
        let v = max(0.15, 1.0 - Double(j) / 28.0)
        return v * 0.9
    }
}
