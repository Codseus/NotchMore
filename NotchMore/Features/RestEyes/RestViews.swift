import SwiftUI

// MARK: - Warning Notification View
struct RestWarningView: View {
    @ObservedObject var restManager: RestManager
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "eye.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Your Eyes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Break in \(Int(restManager.timeRemaining)) seconds")
                    .font(.system(size: 12)) 
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: { restManager.addOneMinute() }) {
                    Text("+1 Min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { restManager.skipBreak() }) {
                    Text("Skip")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            ZStack {
                Color.black.opacity(0.85)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
        .frame(width: 340, height: 70)
    }
}

// MARK: - Blocking Screen View
struct RestBlockingView: View {
    @ObservedObject var restManager: RestManager
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Image(systemName: "eyes")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Take a Rest")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Look away from the screen, relax your eyes, and take a deep breath.")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("\(Int(restManager.timeRemaining))")
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.blue)
                    .padding(.top, 20)
                
                Button(action: { restManager.skipRest() }) {
                    Text("Skip Rest")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 40)
            }
        }
    }
}
