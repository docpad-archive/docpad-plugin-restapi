# Export Plugin Tester
module.exports = (testers) ->
	# PRepare
	pathUtil = require('path')
	{expect} = require('chai')
	superAgent = require('superagent')
	rimraf = require('rimraf')

	# Define My Tester
	class MyTester extends testers.ServerTester
		docpadConfig:
			port: 9779

		# Cleanup
		clean: =>
			# Prepare
			tester = @
			testerConfig = tester.getConfig()

			# Cleanup native comments
			@suite "clean restapi", (suite,test) ->
				test 'clean documents', (next) ->
					rimraf pathUtil.join(testerConfig.testPath, 'src', 'documents'), (err) ->
						return next()  # ignore errors
				test 'clean files', (next) ->
					rimraf pathUtil.join(testerConfig.testPath, 'src', 'files'), (err) ->
						return next()  # ignore errors

			# Chain
			@

		# Test Create
		testCreate: => @clean(); super

		# Custom test for the server
		testServer: (next) ->
			# Prepare
			tester = @

			# Create the server
			super

			# Test
			@suite 'restapi', (suite,test) ->
				# Prepare
				testerConfig = tester.getConfig()
				docpad = tester.docpad
				docpadConfig = docpad.getConfig()
				plugin = tester.getPlugin()
				pluginConfig = plugin.getConfig()

				# Prepare
				apiUrl = "http://localhost:#{docpadConfig.port}/restapi"

				# Post
				sendFile = (method, relativePath, data, next) ->
					# Prepare attributes
					sendUrl = "#{apiUrl}/documents/#{relativePath}"

					# Send the file
					console.log "sending to: #{sendUrl}"
					superAgent[method](sendUrl)
						.type('json').set('Accept', 'application/json')
						.send(data)
						.timeout(30*1000)
						.end(next)

				# Send and check file
				sendFileWithCheck = (method, relativePath, data, attributes, next) ->
					sendFile method, relativePath, data, (err, res) ->
						# Check
						return next(err)  if err

						# Compare
						actual = res.body
						expected =
							success: true
							message: 'Creation completed successfully'
							data: attributes

						# Check
						try
							expect(actual, 'response result should be as expected').to.deep.equal(expected)
						catch err
							console.log actual
							console.log expected
							return next(err)
						return next()


				# Create file test
				test "create a new document", (done) ->
					attributes =
						meta:
							title: 'hello world'
						filename: 'test.html.md'
						relativePath: 'posts/test.html.md'
						url: '/posts/test.html'
						urls: ['/posts/test.html']
						contentType: "text/x-markdown"
						encoding: "utf8"
						content: 'hello *world*'
						contentRendered: "<p>hello <em>world</em></p>\n"

					data =
						title: attributes.meta.title
						content: attributes.content

					sendFileWithCheck('put', 'posts/test.html.md', data, attributes, done)

				# Create file test
				test "create a 2nd new document", (done) ->
					attributes =
						meta:
							title: 'hello world'
						filename: 'test-2.html.md'
						relativePath: 'posts/test-2.html.md'
						url: '/posts/test-2.html'
						urls: ['/posts/test-2.html']
						contentType: "text/x-markdown"
						encoding: "utf8"
						content: 'hello *world*'
						contentRendered: "<p>hello <em>world</em></p>\n"

					data =
						title: attributes.meta.title
						content: attributes.content

					sendFileWithCheck('put', 'posts/test.html.md', data, attributes, done)

				# Create file test
				test "create a 3rd new document", (done) ->
					attributes =
						meta:
							title: 'hello world'
						filename: 'test-3.html.md'
						relativePath: 'posts/test-3.html.md'
						url: '/posts/test-3.html'
						urls: ['/posts/test-3.html']
						contentType: "text/x-markdown"
						encoding: "utf8"
						content: 'hello *world*'
						contentRendered: "<p>hello <em>world</em></p>\n"

					data =
						title: attributes.meta.title
						content: attributes.content

					sendFileWithCheck('put', 'posts/test.html.md', data, attributes, done)

		# Test Custom
		testCustom: => @clean()
