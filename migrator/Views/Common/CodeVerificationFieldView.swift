//
//  CodeVerificationFieldView.swift
//  IBM Data Shift
//
//  Created by Simone Martorelli on 15/03/2024.
//  © Copyright IBM Corp. 2023, 2024
//  SPDX-License-Identifier: Apache2.0
//

import SwiftUI
import Combine

/// This view is used to display a text field that accepts a six-char code.
struct CodeVerificationFieldView: View {
    
    // MARK: - Enums
    
    /// An enum that represents the focus state of an element in the view.
    enum ElementFocusState: Hashable {
        case char(Int)
    }
    
    // MARK: - Focus State Variables
    
    /// The focus state of the view's elements.
    @FocusState private var charFocusState: ElementFocusState?
    
    // MARK: - Binded Variables
    
    /// The binded variable that stores the code entered by the user.
    @Binding private var code: String
    
    // MARK: - State Viariables
    
    /// The state variable that stores the individual characters of the code.
    @State private var chars: [String]
    
    // MARK: - Private Variables
    
    /// A boolean value that indicates whether the view should be displayed in read-only mode.
    private var readOnly: Bool
    
    // MARK: - Initializers
    
    /// Initializes the `CodeVerificationFieldView` with the given parameters.
    /// - Parameters:
    ///   - code: The binded variable that stores the code entered by the user.
    ///   - viewOnly: A boolean value that indicates whether the view should be displayed in read-only mode.
    init(code: Binding<String>, viewOnly: Bool = false) {
        self._code = code
        self._chars = State(initialValue: Array(repeating: "", count: 6))
        self.readOnly = viewOnly
    }
    
    // MARK: - Views
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                if readOnly {
                    Text(chars[index])
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .frame(width: 43, height: 60)
                        .font(.system(size: 36, weight: .semibold))
                        .background(
                            Color("bigButtonUnselected")
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0)
                        )
                } else {
                    TextField("", text: $chars[index])
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .frame(width: 43, height: 60)
                        .font(.system(size: 36, weight: .semibold))
                        .focused($charFocusState, equals: ElementFocusState.char(index))
                        .background(Color("bigButtonUnselected")
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 6, x: 0, y: 0))
                        .onChange(of: chars[index]) { newVal in
                            if newVal.count == 1 {
                                if index < 6 - 1 {
                                    charFocusState = ElementFocusState.char(index + 1)
                                } else {
                                    charFocusState = nil
                                }
                            } else if newVal.count == 6 {
                                code = newVal
                                updateElements()
                                charFocusState = ElementFocusState.char(6 - 1)
                            } else if newVal.isEmpty {
                                if index > 0 {
                                    charFocusState = ElementFocusState.char(index - 1)
                                }
                            }
                            code = chars.joined()
                        }
                        .onTapGesture {
                            charFocusState = ElementFocusState.char(index)
                        }
                        .onReceive(Just(chars[index])) { _ in
                            if chars[index].count > 1 {
                                self.chars[index] = String(chars[index].prefix(1))
                            } else {
                                self.chars[index] = self.chars[index].uppercased()
                            }
                        }
                }
            }
        }
        .onAppear {
            updateElements()
        }
    }
    
    // MARK: - Private Methods
    
    /// Update the single elements of the code with their updated value, starting from the entire code.
    private func updateElements() {
        let tmpArray = Array(code.prefix(6))
        for (index, char) in tmpArray.enumerated() {
            chars[index] = String(char)
        }
    }
}

#Preview {
    CodeVerificationFieldView(code: .constant("543216"), viewOnly: false)
}
