//
//  AuthErrorMapper.swift
//  Locolo
//
//  Turns raw Supabase/network errors into short, human sentences we're happy to
//  show on the auth screens. Raw errors leak implementation detail ("PostgREST
//  error 400", "invalid_grant") and read as broken to a user.
//
//  Security note: sign-in failures deliberately do NOT distinguish "no such
//  account" from "wrong password" — that difference lets anyone enumerate which
//  emails are registered.
//

import Foundation
import Auth

enum AuthErrorMapper {

    /// A friendly message for any error thrown during an auth call.
    /// - Parameter codeSentAt: for `.otp`, when the code was sent. Supabase
    ///   answers a wrong code and an expired code with the same
    ///   "Token has expired or is invalid" (`otp_expired`), so we use the age of
    ///   the code to tell the user which one actually happened.
    static func message(for error: Error, context: Context = .generic, codeSentAt: Date? = nil) -> String {
        if isOffline(error) {
            return "You appear to be offline. Check your connection and try again."
        }
        if isTimeout(error) {
            return "That took too long. Check your connection and try again."
        }

        let raw = rawText(error).lowercased()

        // --- credential / identity ---
        if raw.contains("invalid login") || raw.contains("invalid_grant")
            || raw.contains("invalid credentials") {
            return "That email or password doesn't look right."
        }
        if raw.contains("signups not allowed") || raw.contains("signup_disabled") {
            return "Email sign-up is turned off right now. Try Apple or Google."
        }
        if raw.contains("email not confirmed") || raw.contains("not confirmed")
            || raw.contains("email_not_confirmed") {
            return "Please verify your email first — check your inbox for the code."
        }
        if raw.contains("already registered") || raw.contains("already been registered")
            || raw.contains("user already exists") || raw.contains("duplicate key") {
            switch context {
            case .signUp: return "An account with that email already exists. Try signing in."
            case .username: return "That username is taken. Try another."
            default: return "That's already in use."
            }
        }
        if raw.contains("weak password") || raw.contains("password should be at least")
            || raw.contains("password is too short") {
            return "Use at least 8 characters, with a mix of letters and numbers."
        }
        if raw.contains("invalid email") || raw.contains("unable to validate email") {
            return "That email address doesn't look valid."
        }

        // --- throttling (before OTP: "for security purposes, you can only
        // request this after 42 seconds" mentions neither code nor expiry) ---
        if isRateLimited(error) {
            if let seconds = retryAfterSeconds(raw) {
                return "Please wait \(seconds)s before requesting another code."
            }
            return "Too many attempts. Please wait a minute and try again."
        }

        // --- OTP ---
        if context == .otp || raw.contains("otp") || raw.contains("token") {
            let ambiguous = raw.contains("expired or is invalid") || raw.contains("otp_expired")
                || raw.contains("invalid token") || raw.contains("token is invalid")
            if ambiguous || context == .otp {
                // Codes live for an hour by default (Auth → Email OTP Expiration).
                // A code entered well inside that window that still fails was
                // simply mistyped — or superseded by a newer code.
                if let sentAt = codeSentAt, Date().timeIntervalSince(sentAt) < otpLifetime {
                    return "That code isn't right. Check the most recent email and try again."
                }
                if raw.contains("expired") && codeSentAt != nil {
                    return "That code has expired. Tap Resend to get a new one."
                }
                return "That code isn't right or has expired. Check the latest email, or tap Resend."
            }
        }

        // --- server ---
        if raw.contains("500") || raw.contains("503") || raw.contains("server error") {
            return "Our servers are having a moment. Please try again shortly."
        }

        switch context {
        case .signIn:   return "Couldn't sign you in. Please try again."
        case .signUp:   return "Couldn't create your account. Please try again."
        case .reset:    return "Couldn't send the reset code. Please try again."
        case .otp:      return "Couldn't verify that code. Please try again."
        case .username: return "Couldn't update your username. Please try again."
        case .resend:   return "Couldn't send a new code. Please try again."
        case .social:   return "Couldn't finish signing in. Please try again."
        case .generic:  return "Something went wrong. Please try again."
        }
    }

    enum Context {
        case signIn, signUp, reset, otp, resend, social, username, generic
    }

    /// Matches Supabase's default email OTP expiry (3600 s).
    static let otpLifetime: TimeInterval = 3600

    static func isRateLimited(_ error: Error) -> Bool {
        let raw = rawText(error).lowercased()
        return raw.contains("rate limit") || raw.contains("too many requests")
            || raw.contains("429") || raw.contains("for security purposes")
            || raw.contains("over_email_send_rate_limit")
    }

    /// "…only request this after 42 seconds" → 42
    private static func retryAfterSeconds(_ raw: String) -> Int? {
        guard let range = raw.range(of: #"after (\d+) second"#, options: .regularExpression) else { return nil }
        return Int(raw[range].filter(\.isNumber))
    }

    // MARK: - Helpers

    static func isOffline(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorDataNotAllowed,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost].contains(ns.code)
    }

    static func isTimeout(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut
    }

    /// Errors worth one silent retry (transient transport problems).
    static func isRetryable(_ error: Error) -> Bool {
        isTimeout(error) || {
            let ns = error as NSError
            return ns.domain == NSURLErrorDomain &&
                [NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost].contains(ns.code)
        }()
    }

    private static func rawText(_ error: Error) -> String {
        let ns = error as NSError
        var parts = [error.localizedDescription, ns.domain]
        // Supabase's machine-readable code ("otp_expired", "weak_password", …)
        if let auth = error as? AuthError { parts.append(auth.errorCode.rawValue) }
        for value in ns.userInfo.values {
            parts.append(String(describing: value))
        }
        return parts.joined(separator: " ")
    }
}
