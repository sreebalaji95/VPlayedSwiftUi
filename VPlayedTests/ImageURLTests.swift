import Foundation
import Testing
@testable import VPlayed

struct ImageURLTests {
    let cdn = URL(string: "https://cdn.example.com/")!

    @Test func relativeKeysJoinTheCDN() {
        let url = ImageURL.resolve("gudsho-upload/13-06-2026/a b.jpg", imageBaseURL: cdn)
        #expect(url?.absoluteString == "https://cdn.example.com/gudsho-upload/13-06-2026/a%20b.jpg")
    }

    @Test func absoluteURLsPassThrough() {
        let url = ImageURL.resolve("https://gsvp-dev.s3.ap-south-1.amazonaws.com/static/images/blue.png", imageBaseURL: cdn)
        #expect(url?.host() == "gsvp-dev.s3.ap-south-1.amazonaws.com")
    }

    @Test(arguments: [nil, "", "   "])
    func missingPathsResolveToNil(_ path: String?) {
        #expect(ImageURL.resolve(path, imageBaseURL: cdn) == nil)
    }
}
