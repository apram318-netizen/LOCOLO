//
//  KeyboardObserver.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//



import SwiftUI
import Combine

final class KeyboardObserver: ObservableObject {
    @Published var isKeyboardVisible: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { _ in true }
        
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in false }
        
        // merge and listen
        Publishers.Merge(willShow, willHide)
            .receive(on: RunLoop.main)
            .assign(to: \.isKeyboardVisible, on: self)
            .store(in: &cancellables)
    }
}
