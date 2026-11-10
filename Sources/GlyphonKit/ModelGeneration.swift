/// The generation of the on-device model, which changes with the major
/// system release.
///
/// A new model reads the same prompt differently: the macOS 26 prompts lost
/// a large part of their quality on the macOS 27 model. Each generation has
/// its own prompts, tuned against the eval harness on that system. The
/// prompts of an older generation stay as they are, because they cannot be
/// measured again after the system changes.
enum ModelGeneration: Sendable {
  case os26
  case os27

  static var current: ModelGeneration {
    if #available(macOS 27, iOS 27, *) { .os27 } else { .os26 }
  }
}
