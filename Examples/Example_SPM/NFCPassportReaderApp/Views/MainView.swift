//
//  MainView.swift
//  NFCPassportReaderApp
//
//  Created by Andy Qua on 04/06/2019.
//  Copyright © 2019 Andy Qua. All rights reserved.
//

import SwiftUI
import OSLog
import Combine
import NFCPassportReader
import UniformTypeIdentifiers
import MRZParser

let appLogging = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")


struct MainView : View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) var colorScheme

    @State private var showingAlert = false
    @State private var showingSheet = false
    @State private var showDetails = false
    @State private var alertTitle : String = ""
    @State private var alertMessage : String = ""
    @State private var showSettings : Bool = false
    @State private var showScanMRZ : Bool = false
    @State private var showSavedPassports : Bool = false
    @State private var gettingLogs : Bool = false
    @State private var selectedPasswordType: PACEPasswordType = .mrz
    @State private var canNumber = ""
    // New: control PACE-only polling UI toggle
    @State private var paceOnly: Bool = false

    @State var page = 0
    
    @State var bgColor = Color( UIColor.systemBackground )
    
    private let passportReader = PassportReader()

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    // Authentication Method Picker
                    Picker("Authentication Method", selection: $selectedPasswordType) {
                        Text("MRZ").tag(PACEPasswordType.mrz)
                        Text("CAN").tag(PACEPasswordType.can)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.top)

                    // Show appropriate UI based on selection
                    if selectedPasswordType == .mrz {
                        HStack {
                            Spacer()
                            Button(action: {self.showScanMRZ.toggle()}) {
                                Label("Scan MRZ", systemImage:"camera")
                            }.padding([.top, .trailing])
                        }
                        MRZEntryView()
                    } else {
                        VStack(alignment: .leading) {
                            Text("Card Access Number (CAN)")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top)
                            
                            TextField("Enter 6-digit CAN", text: $canNumber)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)
                                .onChange(of: canNumber) { newValue in
                                    // Limit to 6 digits and ensure only digits
                                    if newValue.count > 6 {
                                        canNumber = String(newValue.prefix(6))
                                    }
                                    canNumber = newValue.filter { $0.isNumber }
                                }
                            
                            Text("The CAN is a 6-digit number printed on your document")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                    }
                    
                    // PACE-only polling toggle
                    Toggle(isOn: $paceOnly) {
                        VStack(alignment: .leading) {
                            Text("PACE only")
                            Text("Use Core NFC PACE polling\n(requires PACE support on document)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    
                    Button(action: {
                        self.scanPassport()
                    }) {
                        Text("Scan Passport")
                            .font(.largeTitle)
                            .foregroundColor(isValid ? .secondary : Color.secondary.opacity(0.25))
                    }
                    .disabled( !isValid )

                    Spacer()
                    HStack(alignment:.firstTextBaseline) {
                        Text( "Version - \(UIApplication.version)" )
                            .font(.footnote)
                            .padding(.leading)
                        Spacer()
                        Button(action: {
                            shareLogs()
                        }) {
                            Text("Share logs")
                                .foregroundColor(.secondary)
                        }.padding(.trailing)
                        .disabled( !isValid )
                    }
                }
                
                if gettingLogs {
                    VStack {
                        VStack(alignment:.center) {
                            Text( "Retrieving logs....." )
                                .font(.title)
                                .frame(maxWidth:.infinity, maxHeight:150)
                        }
                        .shadow(radius: 10)
                        .background(.white)
                        .cornerRadius(20) /// make the background rounded
                        .overlay( /// apply a rounded border
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.gray, lineWidth: 2)
                        )
                        .padding()
                        Spacer()
                    }
                }
            }
            .navigationTitle("Passport details")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {showSettings.toggle()}) {
                            Label("Settings", systemImage: "gear")
                        }
                        Button(action: {self.showSavedPassports.toggle()}) {
                            Label("Show saved passports", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "gear")
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            .alert(isPresented: $showingAlert) {
                    Alert(title: Text(alertTitle), message:
                        Text(alertMessage), dismissButton: .default(Text("Got it!")))
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            // Modern navigation destinations driven by Bool bindings
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $showDetails) {
                PassportView()
            }
            .navigationDestination(isPresented: $showSavedPassports) {
                StoredPassportView()
            }
            .navigationDestination(isPresented: $showScanMRZ) {
                MRZScanner(completionHandler: { mrz in
                    if let (docNr, dob, doe) = parse( mrz:mrz ) {
                        settings.passportNumber = docNr
                        settings.dateOfBirth = dob
                        settings.dateOfExpiry = doe
                    }
                    showScanMRZ = false
                })
                .navigationTitle("Scan MRZ")
            }
        }
    }
}

// MARK: View functions - functions that affect the view
extension MainView {
    
    var isValid : Bool {
        // Updated to handle both MRZ and CAN validation
        if selectedPasswordType == .mrz {
            return settings.passportNumber.count >= 8
        } else {
            return canNumber.count == 6 && canNumber.allSatisfy { $0.isNumber }
        }
    }

    func parse( mrz:String ) -> (String, Date, Date)? {
        print( "mrz = \(mrz)")
        
        let parser = MRZParser(isOCRCorrectionEnabled: true)
        if let result = parser.parse(mrzString: mrz),
           let docNr = result.documentNumber,
           let dob = result.birthdate,
           let doe = result.expiryDate {
            
            return (docNr, dob, doe)
        }
        return nil
    }
}

// MARK: Action Functions
extension MainView {

    func shareLogs() {
        gettingLogs = true
        Task {
            hideKeyboard()
            PassportUtils.shareLogs()
            gettingLogs = false
        }
    }

    func scanPassport( ) {
        lastPassportScanTime = Date.now

        hideKeyboard()
        self.showDetails = false
        
        // Key difference: Prepare parameters based on selected authentication type
        let mrzKeyParam: String?
        let canParam: String?
        
        if selectedPasswordType == .mrz {
            let df = DateFormatter()
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "YYMMdd"
            
            let pptNr = settings.passportNumber
            let dob = df.string(from:settings.dateOfBirth)
            let doe = df.string(from:settings.dateOfExpiry)
            
            let passportUtils = PassportUtils()
            mrzKeyParam = passportUtils.getMRZKey(passportNumber: pptNr, dateOfBirth: dob, dateOfExpiry: doe)
            canParam = nil
        } else {
            mrzKeyParam = nil
            canParam = canNumber
        }

        // Set the masterListURL on the Passport Reader to allow auto passport verification
        let masterListURL = Bundle.main.url(forResource: "masterList", withExtension: ".pem")!
        passportReader.setMasterListURL( masterListURL )
        
        // Set whether to use the new Passive Authentication verification method (default true) or the old OpenSSL CMS verifiction
        passportReader.passiveAuthenticationUsesOpenSSL = !settings.useNewVerificationMethod
        
        // If we want to read only specific data groups we can using:
//        let dataGroups : [DataGroupId] = [.COM, .SOD, .DG1, .DG2, .DG7, .DG11, .DG12, .DG14, .DG15]
//        passportReader.readPassport(mrzKey: mrzKey, tags:dataGroups, completed: { (passport, error) in
        
        appLogging.error( "Using version \(UIApplication.version)" )
        
        Task {
                let customMessageHandler: (NFCViewDisplayMessage)->String? = { (displayMessage) in
                    switch displayMessage {
                        case .requestPresentPassport:
                            return selectedPasswordType == .mrz ?
                                "Hold your iPhone near an NFC enabled passport." :
                                "Hold your iPhone near the document and enter the CAN."
                        default:
                            // Return nil for all other messages so we use the provided default
                            return nil
                    }
                }
                
                do {
                    let passport: NFCPassportModel
                    
                    if selectedPasswordType == .mrz {
                        // Use the original API for MRZ to demonstrate backward compatibility
                        passport = try await passportReader.readPassport(
                            mrzKey: mrzKeyParam,
                            useExtendedMode: settings.useExtendedMode,
                            paceOnly: paceOnly,
                            customDisplayMessage: customMessageHandler
                        )
                    } else {
                        // Use the new API for CAN
                        passport = try await passportReader.readPassport(
                            mrzKey: nil,
                            can: canParam,
                            useExtendedMode: settings.useExtendedMode,
                            paceOnly: paceOnly,
                            customDisplayMessage: customMessageHandler
                        )
                    }
                    
                
                if let _ = passport.faceImageInfo {
                    print( "Got face Image details")
                }
                
                if settings.savePassportOnScan {
                    // Save passport
                    let dict = passport.dumpPassportData(selectedDataGroups: DataGroupId.allCases, includeActiveAuthenticationData: true)
                    if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
                        
                        let savedPath = FileManager.cachesFolder.appendingPathComponent("\(passport.documentNumber).json")
                        
                        try? data.write(to: savedPath, options: .completeFileProtection)
                    }
                }
                
                DispatchQueue.main.async {
                    self.settings.passport = passport
                    self.showDetails = true
                }
            } catch {
                self.alertTitle = "Oops"
                self.alertMessage = error.localizedDescription
                self.showingAlert = true

            }
        }
    }
}

//MARK: PreviewProvider
#if DEBUG
struct ContentView_Previews : PreviewProvider {

    static var previews: some View {
        let settings = SettingsStore()
        
        return Group {
            MainView()
                .environmentObject(settings)
                .environment( \.colorScheme, .light)
            MainView()
                .environmentObject(settings)
                .environment( \.colorScheme, .dark)
        }
    }
}
#endif
