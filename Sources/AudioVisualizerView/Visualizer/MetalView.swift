//
//  MetalView.swift
//  FileProviderSample
//
//  Created by Raheel Ahmad on 6/17/23.
//
//

import MetalKit
import SwiftUI
import Logging

public struct VizView: View {
    private let isSubscribed: Bool
    private let liveReloads: Bool
    private let showOptionsOnHoverOnly: Bool
    private let showSell: (() -> ())

    public init(
        isSubscribed: Bool,
        focused: Binding<Bool>,
        showOptionsOnHoverOnly: Bool = false,
        liveReloads: Bool = false,
        showSell: @escaping (() -> ())
    ) {
        self.isSubscribed = isSubscribed
        self.showSell = showSell
        self.liveReloads = liveReloads
        self._focused = focused
        self.showOptionsOnHoverOnly = showOptionsOnHoverOnly
        let showOptions = !showOptionsOnHoverOnly
        self._showOptions = .init(initialValue: showOptions)
    }

    @EnvironmentObject private var vizDataProcessor: VisualizerDataBuilder
    @State private var viz: Viz = .bars
    @Binding private var focused: Bool
    @State private var showOptions = false

    @ViewBuilder
    private var options: some View {
        Picker(selection: $viz) {
            ForEach(isSubscribed ? Viz.allCases : Viz.locked) { viz in
                switch viz {
                case .bars: Text("bar")
                        .font(.footnote.monospaced())
                        .tag(Viz.bars)
                case .radialFunk: Text("radial")
                        .font(.footnote.monospaced())
                        .tag(Viz.radialFunk)
                case .spectrum: Text("spectrum")
                        .font(.footnote.monospaced())
                        .tag(Viz.spectrum)
                }
            }
        } label: {
            Text("viz")
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    private var sellButton: some View {
        Button {
            showSell()
        } label: {
            Text("PRO")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 0)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(red: 89/255.0, green: 178/255.0, blue: 101/255.0))
                )
        }
    }
    
    private func hideAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                focused = true
            }
        }
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
#if os(macOS)
            MetalSwiftView(viz: $viz, liveReload: liveReloads)
                .onTapGesture {
                    withAnimation {
                        focused.toggle()
                        if !focused {
                            hideAfterDelay()
                        }
                    }
                }
            #else
            MetalSwiftView(viz: $viz)
                .onTapGesture {
                    withAnimation {
                        focused.toggle()
                        if !focused {
                            hideAfterDelay()
                        }
                    }
                }
            #endif
            if showOptions {
                HStack {
                    options
                    if !isSubscribed {
                        sellButton
                    }
                    Spacer()
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.6)))
                .padding(.horizontal, 34)
                .padding(.vertical, 34)
                .zIndex(1)
            }
        }
        .ignoresSafeArea(edges: .all)
        .onHover { hovering in
            guard showOptionsOnHoverOnly else { return }
            self.showOptions = hovering
        }
        .onAppear {
            vizDataProcessor.shouldProduceFrequenciesOnTap = true
            hideAfterDelay()
        }
        .onDisappear {
            vizDataProcessor.shouldProduceFrequenciesOnTap = false
        }
    }
}

#if os(iOS)
private struct MetalSwiftView: UIViewRepresentable {
    @Binding var viz: Viz
    @EnvironmentObject var vizProcessor: VisualizerDataBuilder

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()

        let renderer = context.coordinator
        renderer?.setup(view, dataProcessor: vizProcessor)
        vizProcessor.renderInfoProvider = renderer
        vizProcessor.prepare()
        view.delegate = renderer

        return view
    }

    func makeCoordinator() -> Renderer? {
        Renderer(failable: true)
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let renderer = context.coordinator
        if viz != renderer?.viz {
            renderer?.viz = viz
        }
    }
}
#elseif os(macOS)

private struct MetalSwiftView: NSViewRepresentable {
    @Binding var viz: Viz
    let liveReload: Bool
    @EnvironmentObject var vizProcessor: VisualizerDataBuilder

    func makeNSView(context: Context) -> some NSView {
        let view = MTKView()

        let renderer = context.coordinator
        renderer?.setup(view, dataProcessor: vizProcessor)
        vizProcessor.renderInfoProvider = renderer
        vizProcessor.prepare()
        view.delegate = renderer

        return view
    }

    func makeCoordinator() -> Renderer? {
        Renderer(failable: true, liveReload: liveReload)
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {
        let renderer = context.coordinator
        if viz != renderer?.viz {
            renderer?.viz = viz
        }
    }
}
#endif
