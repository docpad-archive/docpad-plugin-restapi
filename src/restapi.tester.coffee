# Export Plugin Tester
module.exports = (testers) ->
	# PRepare
	pathUtil = require('path')
	{expect} = require('chai')
	superAgent = require('superagent')
	superAgent['delete'] = superAgent.del
	rimraf = require('rimraf')

	# Define My Tester
	class MyTester extends testers.ServerTester
		#docpadConfig:
		#	port: 9779

		# Cleanup
		clean: =>
			# Prepare
			tester = @
			testerConfig = tester.getConfig()

			# Cleanup
			@suite "clean restapi", (suite,test) ->
				test 'remove src', (next) ->
					rimraf pathUtil.join(testerConfig.testPath, 'src'), (err) ->
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
							message: null
							data: responseData

						# Clean
						switch method
							when 'delete'
								expected.message = 'Delete completed successfully'
							when 'post'
								expected.message = 'Update completed successfully'
							when 'put'
								expected.message = 'Creation completed successfully'
							when 'get'
								actual.message =
								expected.message = 'Overwritten as this changes'

						# Check
						try
							expect(actual, 'response result should be as expected').to.deep.equal(expected)
						catch err
							console.log JSON.stringify(actual, null, '  ')
							console.log JSON.stringify(expected, null, '  ')
							return next(err)
						return next()

				# Collections
				suite 'collections', (suite,test) ->
					test 'check listing', (done) ->
						responseData = 'database documents files layouts html stylesheet'.split(' ').map (collectionName) ->
							{name: collectionName, length: 0, relativePaths: []}
						requestData = {}
						requestWithCheck('get', 'collections/', requestData, responseData, done)

				# Create files
				suite 'create', (suite,test) ->
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
						requestWithCheck('put', "collection/documents/posts/test.txt", requestData, responseData, done)

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
						requestWithCheck('put', "collection/documents/posts/test.html", requestData, responseData, done)

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
						requestWithCheck('put', "collection/documents/posts/test.html.md", requestData, responseData, done)

					# Check listing
					test 'check listing', (done) ->
						responseData = files
						requestData = {}
						requestWithCheck('get', 'collection/documents/', requestData, responseData, done)

				# Delete files
				suite 'delete', (suite,test) ->
					test 'delete last document', (done) ->
						responseData = [files.pop()]
						requestData = {}
						requestWithCheck('delete', 'collection/documents/posts/test-3.html.md', requestData, responseData, done)

					test 'check listing', (done) ->
						responseData = files
						requestData = {}
						requestWithCheck('get', 'collection/documents/', requestData, responseData, done)

				# Update files
				suite 'update', (suite,test) ->
					test 'update last document', (done) ->
						file = files[files.length-1]
						file.meta.title = 'hello WORLD'
						responseData = file
						requestData = file.meta
						requestWithCheck('post', 'collection/documents/posts/test-2.html', requestData, responseData, done)

					test 'check listing', (done) ->
						responseData = files
						requestData = {}
						requestWithCheck('get', 'collection/documents/', requestData, responseData, done)


		# Test Custom
		testCustom: => @clean()
