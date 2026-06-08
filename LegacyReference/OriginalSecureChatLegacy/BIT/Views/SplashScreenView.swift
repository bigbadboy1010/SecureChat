import SwiftUI

struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    @State private var showLoadingBar = false
    @State private var loadingProgress: Double = 0
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.12),
                    Color(red: 0.15, green: 0.15, blue: 0.17)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Logo with animation
                VStack(spacing: 12) {
                    ZStack {
                        // Rotating circle background
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.green.opacity(0.3),
                                        Color.blue.opacity(0.3)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(Double(showLoadingBar) ? 360 : 0))
                            .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: showLoadingBar)
                        
                        // Lock Icon
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .scaleEffect(scale)
                    .opacity(opacity)
                    
                    Text("BIT SecureChat")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                        .opacity(opacity)
                    
                    Text("Ende-zu-Ende-Verschlüsselt")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                        .opacity(opacity)
                }
                
                Spacer()
                
                // Loading indicator
                if showLoadingBar {
                    VStack(spacing: 12) {
                        ProgressView(value: loadingProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(height: 2)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            
                            Text("App wird initialisiert...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.green.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 24)
                    .opacity(opacity)
                }
                
                // Security info
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("AES-256-GCM Verschlüsselung")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("Double-Ratchet Algorithmus")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("Dezentrale Architektur")
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .foregroundColor(.green.opacity(0.7))
                .padding(.horizontal, 24)
                .opacity(opacity)
                
                Spacer()
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            // Initial animation
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
            
            // Start loading sequence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                showLoadingBar = true
                
                // Simulate loading progress
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                    if loadingProgress < 0.9 {
                        loadingProgress += Double.random(in: 0.01...0.08)
                    } else {
                        timer.invalidate()
                    }
                }
            }
            
            // Complete splash screen after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    opacity = 0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    SplashScreenView {
        print("Splash screen completed")
    }
}
