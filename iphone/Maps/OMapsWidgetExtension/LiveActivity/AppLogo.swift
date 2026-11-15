import SwiftUI

struct AppLogo: View {
  var body: some View {
    Image("MikshatLogo")
      .renderingMode(.original)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .accessibilityLabel(Text("مكشات"))
  }
}
