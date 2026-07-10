//
//  MainView.swift
//  Overwall
//
//  Created by Ng1nx on 7/10/26.
//

import SwiftUI

struct MainView: View {
    @State var isOnVPN: Bool = false
    
    var body: some View {
        Form {
            Toggle("Toggle", isOn: $isOnVPN)
        }.scrollContentBackground(.hidden)
            .background(Color.background)
    }
}


#Preview {
    ContentView()
}
