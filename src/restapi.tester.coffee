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
				files = []

				# Prepare
				apiUrl = "http://localhost:#{docpadConfig.port}/restapi"

				# Request
				request = (method, relativeUrl, requestData, next) ->
					absoluteUrl = apiUrl+'/'+relativeUrl
					console.log "#{method} to #{absoluteUrl}"
					superAgent[method](absoluteUrl)
						.type('json').set('Accept', 'application/json')
						.send(requestData)
						.timeout(30*1000)
						.end(next)

				# Send and check file
				requestWithCheck = (method, url, requestData, responseData, next) ->
					request method, url, requestData, (err, res) ->
						# Check
						return next(err)  if err

						# Compare
						actual = res.body
						expected =
							success: true
							message:
								switch method
									when 'delete'
										'Delete completed successfully'
									when 'post'
										'Update completed successfully'
									when 'put'
										'Creation completed successfully'
									when 'get'
										'Listing of documents at  completed successfully'
							data: responseData

						# Check
						try
							expect(actual, 'response result should be as expected').to.deep.equal(expected)
						catch err
							console.log actual
							console.log expected
							return next(err)
						return next()

				# Create files
				suite 'create files', (suite,test) ->
					# Create file test
					test "create a new document", (done) ->
						responseData =
							meta:
								title: 'hello world'
							filename: 'test.txt'
							relativePath: 'posts/test.txt'
							url: '/posts/test.txt'
							urls: ['/posts/test.txt']
							contentType: "text/plain"
							encoding: "utf8"
							content: 'hello *world*'
							contentRendered: 'hello *world*'

						requestData =
							title: responseData.meta.title
							content: responseData.content

						files.push(responseData)
						requestWithCheck('put', "documents/posts/test.txt", requestData, responseData, done)

					# Create file test
					test "create a 2nd new document", (done) ->
						responseData =
							meta:
								title: 'hello world'
							filename: 'test-2.html'
							relativePath: 'posts/test-2.html'
							url: '/posts/test-2.html'
							urls: ['/posts/test-2.html']
							contentType: "text/html"
							encoding: "utf8"
							content: 'hello *world*'
							contentRendered: 'hello *world*'

						requestData =
							title: responseData.meta.title
							content: responseData.content

						files.push(responseData)
						requestWithCheck('put', "documents/posts/test.html", requestData, responseData, done)

					# Create file test
					test "create a 3rd new document", (done) ->
						responseData =
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

						requestData =
							title: responseData.meta.title
							content: responseData.content

						files.push(responseData)
						requestWithCheck('put', "documents/posts/test.html.md", requestData, responseData, done)

				# List files
				suite 'list files', (suite,test) ->
					test 'list documents', (done) ->
						responseData = files
						requestData = {}
						requestWithCheck('get', 'documents/', requestData, responseData, done)

		# Test Custom
		testCustom: => @clean()
