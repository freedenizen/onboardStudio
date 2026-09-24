/// Marketing version of Onboard Studio.
///
/// Hand-maintained: the release workflow passes the tag to `bundle-app.sh`, which overrides
/// `MARKETING_VERSION` for the *bundle* only — nothing rewrites this constant. It is what
/// `onboard --version` and the launcher report, and it drifted to 0.18.1 while 0.19.0 shipped,
/// so `marketingVersionMatchesTheProjectFile` now ties it to `project.yml`.
public enum OnboardStudioVersion {
    public static let marketing = "0.26.0"
}
