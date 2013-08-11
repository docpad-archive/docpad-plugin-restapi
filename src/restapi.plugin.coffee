# Export Plugin
module.exports = (BasePlugin) ->

	#Plugin Globals
	fs = require('fs')

	# Define Plugin
	class RestAPI extends BasePlugin

		# Plugin name
		name: 'restapi'
		config:
			path: '/restapi/'
			maxFilenameLen: 40

		#Add all REST Routes
		serverExtend: (opts) ->
			docpad = @docpad
			config = @getConfig()
			database = docpad.getDatabase()
			docpadConfig = docpad.getConfig()
			server = opts.server
			fsPath = docpadConfig.documentsPaths[0] + '/'
			maxFileLen = @config.maxFileLen

			#Write, Update, and Delete Helper Functions
			findUniqueFilename = (filename) ->
				count = 1
				origFilename = filename
				while(docpad.getFile(relativePath: filename))
					filename = origFilename.replace(/([^ .]*)(\.)?/, '$1' + '-' + (++count) + '$2')
				filename

			fixFilePath = (str) ->
				str?.trim().split(' ').join('-').substring(0, maxFilenameLen).toLowerCase()

			getFilenameFromReq = (req) ->
				fixFilePath(req.params[0] or req.body.filename or req.body[req.body.primaryid])

			getFile = (req) ->
				docpad.getFile(relativePath: (if typeof req == 'string' then req else getFilenameFromReq(req)))

			updateFile = (file, req, res, successMsg = 'Updated') ->
				#Setup and error out if in bad state
				unless file
					return res.send(success: false, message: 'File does not exist')

				#Add any custom meta attributes
				for own key, value of req.body
					file.setMeta(key, value)  unless key in ['filename', 'primaryid', 'content']

				#Return the file to the user
				#This will trigger regeneration
				file.writeSource {cleanAttributes: true}, (err) ->
					console.log err  if err
					res.send(success: !err, message: err or successMsg, filename: file.get('fullPath').replace(fsPath, ''))

			#DELETE:
			#Remove an existing file
			server.delete @config.path + '*' , (req, res) ->
				#Setup and error out if in bad state
				unless filename = getFilenameFromReq(req)
					return res.send(success: false, message: 'Please specify a filename')
				file = getFile(filename)
				unless file
					return res.send(success: false, message: 'File does not exist')

				#If all good, remove the file from the DB
				database.remove(file)
				file.delete (err) ->
                	console.log err  if err
                	res.send(success: !err, message: err or 'Deleted', filename: filename)

			#UPLOAD
			#Handle file uploads posted to /upload
			server.post @config.path + 'upload', (req, res) ->
				successful = []
				failed = []
				currentlyUploading = []
				count = 0

				uploadFile = (file) ->
					path = file.path
					origName = name = docpadConfig.filesPaths[0] + '/' + file.name
					renameCounter = 0

					#save an uploaded file
					save = ->  fs.rename path, name, (err) ->
						unless err
							if renameCounter
								successful.push
									origName: file.name
									newName: name.replace(docpadConfig.filesPaths[0] + '/', '')
							else
								successful.push
									name: file.name
						else
							console.log err
							failed.push
								file: file.name
								error: err
						unless --count
							if successful.length + failed.length is 1
								return res.send(if successful.length then (success: successful) else (success: false, error: failed))
							res.send
								success: successful
								error: failed

					#save an uploaded file with a unique name
					saveUnique = (exists) ->
						#Name is not unique, try again
						if (exists or currentlyUploading.indexOf(name) > -1)
							name = origName.replace(/(.*?)(\..*)/, '$1-' + (++renameCounter) + '$2')
							return fs.exists(name, saveUnique)
						#Unique name found, let's save it
						currentlyUploading.push(name);
						save()

					#save each uploaded file
					fs.exists(name, saveUnique)

				#Iterate through each uploaded file
				for own key of req.files
					if req.files[key].name
						count++
						uploadFile req.files[key]
				#If no work to be done, let the user know
				unless count
					res.send(error: 'No Files specified')

			#CREATE or UPDATE
			#Create or update a file in the docpad database (as well as on the file system) via the REST API
			server.post @config.path + '*' , (req, res) ->
				if req.body.update
					return updateFile(getFile(req), req, res)

				#Get the filename
				unless filename = getFilenameFromReq(req)
					return res.send(success: false, message: 'Please specify a filename')

				#Set up our new document
				documentAttributes =
					data: req.body.content or ''
					fullPath: fsPath + findUniqueFilename(filename)

				# Create the document, inject document helper and add the document to the database
				document = docpad.createDocument(documentAttributes)
				# Inject helper and add to the db
				config.injectDocumentHelper?.call(me, document)
				database.add(document)
				#Add metadata
				updateFile(document, req, res, 'Saved')


			# A helper function that takes a docpad file and outputs an object with desired fields from the file
			fetchFields = (req, file) ->
				#Return immediately if the user wants all attributes
				req.query.af = req.query.af or req.query.fields or req.query.additionalFields or req.query.additionalfields
				if (Array.isArray req.query.af and req.query.af[0] is 'all') or req.query.af is 'all'
					return file.attributes

				#Defaults
				meta = file.meta
				meta.content = file.attributes.content or meta.content
				fields =
					filename: file.attributes.id
					url: file.attributes.url
					meta: file.meta
					contentType: file.attributes.outContentType
					encoding: file.attributes.encoding
					renderedContent: file.attributes.contentRendered

				unless Array.isArray req.query.af
					req.query.af = if req.query.af then [req.query.af] else []
				#Add additional fields the user has requested to the output
				len = req.query.af.length
				while len--
					field = req.query.af[len]
					fields[field] = file.attributes[field]

				#Return the data
				fields

			# A helper function that gets a collection based on request filters and sorting options
			getFilteredCollection = (req) ->
				filter = {}
				sort = {}
				filterObject = if req.query.filter then JSON.parse(req.query.filter) else {}

				# Beware: the filter is applied on the attributes of the file, not the META which is what the user is getting!
				for own key of filterObject
					if Array.isArray(filterterObject[key])
						filter[key] = $in: filterObject[key]
					else
						filter[key] = filterObject[key]
				# Add our special filters
				for own key of req.query._filter
					filter[key] = req.query._filter[key]

				sort[req.query.sort or 'date'] = req.query.sortOrder or -1
				collection = if req.params.type and req.params.type.toLowerCase() != 'all' then docpad.getCollection(req.params.type or 'documents') else database
				#Return the data
				if collection then collection.findAll(filter, sort) else models: []

			### READ
				a method to get files from the docpad database
				Usage:
					/all/	 															Get a listing of the entire docpad database
					/documents/  														Get a listing of the documents collection
					/{collectionName}/  												Get a listing of the {collectionName} collection
					/{collectionName}/{fileName}  										See info about a specific file
					/{collectionName}[/relative/path/]  								Get a listing of the {collectionName} collection filtered by relativePath
					/files/ ->															Get a listing of the files collection
					/files/[images|videos]/ 											Get a listing of all images or videos in the files collection
				Optional Query String params
					pageSize 	 	eg  Number: 10										The size of listing page returned
					page 			eg  Number: 10										The listing page number to be returned
					filter 			eg  JSON: {'relativePath': $startsWith: 'a' }		A Query Engine filter to be applied to the collection being retuned

			###
			server.get @config.path + ':type?/*', (req, res) ->
				#Setup Defaults
				if req.params.type
					req.params.filename = req.params[0]
				else
					req.params.type = req.params[0]
					req.params.filename = ''
				#The user is probably looking for a specifc file
				if req.params.filename
					req.params.type = 'files'  if req.params.type is 'file' or (req.params[0] is 'file' and req.params.filename is '')
					#Create special filters for file MIME tyeps
					if req.params.type.toLowerCase() is 'files'
						filename = req.params.filename.toLowerCase().replace(/\/|\s/g, '')
						if filename is 'images' or filename is 'image'
							req.query._filter = outContentType: $startsWith: 'image/'
						else if filename is 'videos' or filename is 'video'
							req.query._filter = outContentType: $startsWith: 'video/'
					#The user is looking for a directory of files
					if req.params.filename.lastIndexOf('/') is req.params.filename.length - 1
						req.query._filter = relativePath: $startsWith: req.params.filename

					#If the user is looking for a specific file, get that file
					unless req.query._filter
						file = docpad.getFile(relativePath: req.params.filename)
						data = if file then fetchFields(req, file) else []

				#If you don't already have a file to return, find a paged collection to return using the remaining req info
				unless data
					collection = getFilteredCollection(req)
					oldLen = collection.models.length
					#Do paging
					if req.query.pageSize and req.query.page
						collection.models = collection.models.slice(req.query.pageSize * (req.query.page - 1), req.query.pageSize * req.query.page)
					i = 0
					data = []
					newLen = collection.models.length
					while i < newLen
						data.push fetchFields(req, collection.at(i++))
					#Add paging metadata
					data = length: oldLen, data: data
					data.pages = Math.ceil(oldLen / req.query.pageSize)  if req.query.pageSize and req.query.page

				#Return the result to the user
				res.send data

			#Chain
			@