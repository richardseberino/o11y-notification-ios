//
//  ContentView.swift
//  Dyntrace Problems App
//
//  Created by Richard Marques on 31/05/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = InstanceStore()

    var body: some View {
        InstanceListView()
            .environmentObject(store)
    }
}

#Preview {
    ContentView()
}
