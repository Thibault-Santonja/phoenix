# Towards Maintainable Elixir: Testing

In the final article of this series we'll take a look at our approach to testing at [Very Big Things](http://verybigthings.com). As always, when discussing some practice or technique, it's worth defining the purpose, i.e. the benefits that we want to reap. When it comes to tests, we write them to verify that the system is working as expected. A good test suite will fail when something is off in the behaviour of the system. If everything works correctly, all of the tests should pass.

It's of course impossible to reach that ideal. There will always be some bugs that aren't caught by our tests. But the closer we get to this perfection, the more confident can we be that our system is working correctly. Confidence is the most important benefit we get from our tests.

When we're confident in our tests, we're more open to make the internal changes such as optimizations or refactoring. The latter is particularly important to keep the code maintainable.

Focusing on confidence affects the way we write our tests. As you'll see, we take a somewhat different approach compared to various testing advice that can be found in the wild. I want to stress upfront that this approach is not a general pattern which will fit every possible scenario. That said, we had good experiences with it, possibly due to the nature of our projects, which are not very large, and where most of the logic is imperative.

## The level of testing

Suppose we want to test the account registration in a forum backend. We could do this by testing the behaviour of the core function `Forum.Account.register`, which should be straightforward enough. In the test we invoke the function and assert the return value.

However, no matter how extensively we test the core API, such tests won't verify that the corresponding interface layer logic is working correctly. Therefore, we need to introduce a couple of interface-level tests. At the very least, we need one test per each return type. For example, if the function returns `{:ok, Account.t()} | {:error, Ecto.Changeset.t()}`, we'll need one happy path test and one error test.

This leads to some unavoidable overlap between different tests. The two tests at the interface level, such as REST, cover everything that is already verified by the similar core-level tests. And yet, we can't drop the REST-level tests. We could instead remove the two core-level tests, but that would make the code organization confusing, since the tests that verify a single behaviour will be scattered across multiple test modules.

To reduce these issues, we opted for a different strategy. By default we'll start writing all our tests at the interface level, moving deeper only when it's really needed. In practice, most of our tests will operate at the interface level. As a result, we'll get maximum confidence with less tests, and no overlapping.

## Clarifying the intention

Let's see this in action. The following code demonstrates a happy path registration REST-level test:

This test is reasonably short, but it contains a bit of noise. Our intention to register a new user is somewhat obfuscated by the mechanics of building a conn, issuing a request, and decoding the response. We can reduce this noise with the help of a private function:

The `register` function builds the conn and makes the request. It also normalizes the response, which involves decoding the JSON and atomizing the keys. This requires a bit of smartness, but it helps clarifying the test intention.

One annoying issue with this helper function is that we need to provide all of the params. This can become cumbersome and noisy, especially if the operation requires many input parameters. In practice, in most tests only a small subset of the input params is relevant. For example, suppose we want to test that an error is reported if `login` is `nil`. In this case we don't care about other registration params, but we still want them to be provided and valid.

The solution is to make the `register` function automatically generate valid params, and accept overrides:

Note that we're using `System.unique_integer` to introduce uniqueness where needed. This reduces the chance of possible database level locks, and promotes concurrent test execution. With the new version of `register` we can now add a concise error test:

Typically, we start by placing such helper functions as close to the test code as possible, which means in the same describe block. If multiple describe blocks use some function, it will be moved to the end of the test module. If multiple test modules need the same functionality, it will be moved to a test-only helper module (located under test/support), for example `ForumTest.RestClient`.

## Arrange, Act, Assert

In our tests we try to follow the [AAA pattern](https://wiki.c2.com/?ArrangeActAssert=) as much as possible. A test should start by bringing the system into the desired state (Arrange). This is followed by invoking an operation the behaviour of which is being tested (Act). Finally the test performs a set of checks to verify the outcome of the operation (Assert).

The purpose of the small helper functions, such as `register`, is to make this flow clearer. They allow us to highlight the information that is actually relevant for the test in the test code, pushing the rest of the boilerplate deeper.

Let's see this in action. Suppose we want to test the authenticate operation. Here's how the test could look like:

In this version we're using the small fail-fast wrapper around the previously introduced `register` function, which will crash if the registration fails. In other words, in the authentication test we assume that the registration works. This operation is tested elsewhere. Consequently, a bug in registration may cause other tests to fail. This is somewhat unfortunate, but not particularly problematic in practice. Basically, if many tests fail due to a single bug, a developer can start working on one test, and fixing it should fix other tests too.

## Testing the behaviour

The previous test presents an important part of our approach to testing. We want to test the expected behaviour of the system, not implementation details. The focus on the behaviour starts with the description which states that a "registered user can authenticate with correct credentials", and is further clearly explained in the test code.

Because we focus on the behaviour, our test code typically won't use the Repo module directly. Instead, we rely on the public API to bring the system into the desired state, and verify the outcome of the action.

Consider the following example, a slight variation of our register/login functionality. Suppose we need to support the account activation flow, where a user can only authenticate after they have activated the account by clicking on the link sent to them via e-mail. Here's how this test could look like:

The key bit here is how activation is performed. Instead of setting some boolean flag in the database, we'll adapt the `register!` function to return the activation mail. Then we'll invoke another helper function that activates the account. Under the hood, this function will extract the activation link using a regex, and then issue a GET request to the given path, effectively activating the account through the public facing API.

## Performance considerations

Going through the interface layer affects the execution time, since we have to deal with the input encoding and response decoding, and since the requests goes through the entire Plug pipeline.

Another impact on the test speed is caused by the fact that in the arrange phase each test sets up the system state from scratch. For example, let's say that we want to test an authenticated operation, such as `create_post`. To do that, we need to register, activate, and authenticate a user in the arrange phase. This will involve steps such as hashing the password twice (in registration and authentication), performing a regex extraction of the activation link, one database insertion, one database update, and one database lookup. Since most of the operations require an authenticated user, this flow will be frequently performed.

All of this can add up and have a significant effect on the total test execution time. In practice, we didn't experience issues in our projects. Going through the interface layer doesn't seem to add a significant overhead since pre-controller plugs are typically very fast, and most tests deal with small inputs and outputs, so the encoding/decoding overhead is small.

The arrange phase is also typically fast enough for us. The database is running locally, and owing to the `Ecto.Sandbox` adapter, each test is effectively working on an empty database, which leads to pretty fast database operations. Finally, we strive to generate the unique data in each test, which reduces db-level locks, and promotes concurrent execution of tests.

But perhaps the most important reason why this approach works for us is that we're more tolerant about the speed of our tests. We don't obsess about sub-second total execution time. Our threshold is more in the area of 30 seconds for the entire suite, though of course this depends on the project size and the number of tests. It would be great to have blazing fast tests that can be auto-executed whenever a file is saved, but not at the expense of test confidence and code clarity, which are for us much more important properties.

That being said, I definitely don't advocate ignoring the speed of the tests. A test suite which runs for more than a minute can considerably disrupt the development flow. While the presented testing technique has been working well for us so far, it doesn't scale well with the number of tests, and it may not be appropriate for property-based testing. In both cases a small per-test overhead might add up and lead to unacceptable total duration. For example, a single 10ms overhead per single test leads to a 1 second overhead for a single property (with 100 generated inputs), which could very quickly bring us into the minutes range. In such situations different choices might be required.

One possibility is pre-seeding the test database to reduce the amount of db insertions in the arrange phase. Another option is doing extensive tests at the deeper level, to eliminate some overhead. This can work particularly well if some amount of logic can be extracted into a well-defined pure-functional abstraction that doesn't rely on the database or other external services. The behaviour of such abstraction can typically be tested much faster. We didn't have to make such choices so far, which I think demonstrates that our approach can work well in small to medium projects, but these options are always on the table, and we can reach for them if they make sense.

## Test doubles

Our position is that test doubles (stubs and mocks) introduce a mismatch between the reality and the tests, and therefore reduce our confidence. In addition, a double reduces code clarity, because of the extra indirection level. Consequently, we strive to minimize the amount of test doubles. We mostly reach for them to fake a remote service, with the intention of speeding up the test execution and removing possible false positives which can happen if a remote service is not available.

On the other hand we avoid introducing doubles to increase test coverage. Instead, we aim to maximize our coverage organically by focusing on the observable behaviour of the external API. If some execution branch can't easily be triggered through the external API, we'll add complementary tests at the deeper level. It's worth mentioning that we don't obsess about 100% coverage (or any other percentage). We occasionally look at the coverage to see if some important tests are missing, but that's as far as we go.

At this point, many developers might say that most of our tests are integration tests, since they typically involve collaboration between multiple abstractions. We see it a bit differently, using the original meaning of the term "unit test", where the word unit refers to the test, not to the thing being tested. A test is a unit if it is isolated from other tests, which means that it doesn't affect their outcome. Ideally multiple unit tests can be safely executed concurrently. Since we're testing a concurrent system, some tests which interact with global parts of the system (e.g. a named `GenServer`) might need to run sequentially. We still treat such tests as units as long as they don't compromise the outcome of other tests.

An integration test to us is a test which interacts with the components that are otherwise doubled. For example, we could fake an external service in most tests, having only a couple of integration tests which interact with the "real thing". Since we don't want the mergeability of our PRs to be affected by potential unavailability of the remote service, we'd typically run such tests outside of the standard PR flow, for example once a day.

## Summary

As has been repeatedly mentioned, the main property we want from our tests is confidence. We want our tests to fail when the system is misbehaving, and otherwise we want them to pass. Such tests don't get in the way of frequent refactoring, a practice which is important to keep the design in check as the project grows and our understanding of the domain expands. Testing the behaviour at the external API level takes us there.

We also want our test code to be clear. Test code is code, so it should be held to the same level of scrutiny with respect to maintainability. Tests typically have a simpler, imperative flow that can be clearly expressed with the AAA pattern. Clarifying such code mostly requires hiding noisy mechanics behind well-named helper functions.

Our approach leads to somewhat slower tests, though in practice we find the execution times acceptable. Testing speed is important, but not as much as confidence and code clarity. Maximizing concurrent execution by generating unique test data is our main technique for keeping the tests reasonably fast.

Finally, it's worth mentioning that we don't enforce the TDD approach of writing tests first, but we also don't forbid it. We respect the fact that different people prefer different flows, so we're not prescriptive about the process, only about the desired properties of our tests.
