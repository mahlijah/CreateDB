#++++++++++++++++++++++++++++++++++
# Functions
# All JavaScript should be written
# with double quotes!!!!!!!!!!
#++++++++++++++++++++++++++++++++++
function MongoConnectionString {
        Param(
            [string][Parameter(Mandatory=$True)]$MongoDBPrefix,
            [string][Parameter(Mandatory=$True)]$MongoDBUserName,
            [string][Parameter(Mandatory=$True)]$MongoDBPassword,
            [string][Parameter(Mandatory=$True)]$MongoSHost,
            [string][Parameter(Mandatory=$False)]$MongoSPort = '27017',
            [string][Parameter(Mandatory=$True)]$MongoAuthDB,
            [bool][Parameter(Mandatory=$True)]$IntegratedSecurity,
            [string][Parameter(Mandatory=$True)]$MongoParams
        )
    
            if($IntegratedSecurity -eq $True)
            {
                $MongoURL = $MongoDBPrefix + $MongoSHost + ':' + $MongoSPort + '/' + $MongoAuthDB + $MongoParams
            }
            else
            {
                $MongoURL = $MongoDBPrefix + $MongoDBUserName + ':' + $MongoDBPassWord + '@' + $MongoSHost + ':' + $MongoSPort + '/' + $MongoAuthDB + $MongoParams
            }
    
            return $MongoURL
    }
    
    function MongoDBCommand {
        Param(
            [string][Parameter(Mandatory=$True)]$ConnectionString,
            [string][Parameter(Mandatory=$True)]$ScriptJS,
            [Parameter(Mandatory=$True)]$SSHSession
               
        )
        $FullMongoCommand = "mongo " + $FullMongoURL + "'$ScriptJS'"
         
            # Run Mongo commands.
            $result = Invoke-SSHCommand -SSHSession $SSHSession -Command $FullMongoCommand -TimeOut 300 -ErrorAction Stop
            # Minimal error handling
            if ($result.ExitStatus -gt 0) {
                    # Closing SSH session
                    Remove-SSHSession $sshSession.SessionId
                    # Throw error when bash or JS fail
                    throw $result.Error + $result.Output
            } else {
            $ReturnObject = $result.Output | ConvertFrom-Json -ErrorAction Stop
            return $ReturnObject
            }
          
    }
    
    function DBExists
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function dbExists(adminDB, DBName){
            // need to use the connection to the admin database
            var dbs = db.adminCommand("listDatabases");
            // create results object
                    var obj = {
                    result: false,
                    log: ""
                    }
            // Looping through the list of available databases
            for (var i = 0; i < dbs.databases.length; i++) {
                    if (dbs.databases[i].name === DBName) {
                            obj.log = "Found database :: " + dbs.databases[i].name;
                            obj.result = true;
                            break;
                    }
            }
            if (!obj.result) {
                    obj.log = "Database not found :: " + DBName;
                    obj.result = false;
            }
            printjson(obj);
    })(db,"$DBName");
"@
    
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
    }
    
    function IsDBSharded
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function isDBSharded(adminDB, DBName) {
        // switch to config db
        var configDB = adminDB.getSiblingDB("config");
        // create results object
                var obj = {
                result: false,
                log: ""
                }
        // the find mongodb method returns a cursor added toArray to keep variable in play
        var dbs = configDB.databases.find().toArray();
        for (var i = 0; i < dbs.length ; i++) {
                if (dbs[i]._id === DBName) {
                        var status = dbs[i].partitioned;
                        break;
                }
        }
        if (status){
                obj.result = true;
                obj.log = "Sharding is enabled on database :: " + DBName;
        } else {
                obj.log = "Sharding is not enabled on database :: " + DBName;
        }
        printjson(obj);
    })(db,"$DBName")
"@
            
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
    }
    
    function ShardDB
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function shardDB(adminDB, DBName) {
    // create results object
    var obj = {
            result: false,
            log: ""
            }
    //enable sharding
    var response = adminDB.adminCommand({ enableSharding : DBName });
            if (response.ok === 1) {
                    obj.result = true;
                    obj.log = "Sharding has been enabled on database :: " + DBName;
            } else {
            obj.log = response.errmsg;
            }
        printjson(obj);
    })(db,"$DBName");
"@
    
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
    function CollectionExists
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function collectionExists(adminDB, DBName, collectionName) {
            // create results object
                    var obj = {
                    result: false,
                    log: ""
                    }
            // change db to the database to query
            var db = adminDB.getSiblingDB(DBName);
            // get all existing collections from the database
            var collections = db.getCollectionNames();
            // loop through all collections to find the one passed
            for (var i = 0; i < collections.length; i++) {
                    if (collections[i] === collectionName) {
                            obj.log = "Collection " + DBName + "." + collectionName + " :: has been found"
                            obj.result = true;
                            break;
                    }
            }
            if (!obj.result) {
                    obj.log = "Collection " + DBName + "." + collectionName + " :: not found"
            }
            printjson(obj);
    })(db,"$DBName","$CollectionName");
"@
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
    function CreateCollection
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function createCollection(adminDB, DBName, collectionName) {
        // create results object
        var obj = {
            result: false,
            log: ""
            }
        // change db to the database to create
            var db = adminDB.getSiblingDB(DBName); 
            var response = db.createCollection(collectionName);
            if (response.ok === 1) {
                    obj.result = true;
                    obj.log = "Collection " + DBName + "." + collectionName + " :: has been created"
            } else {
            obj.log = response.errmsg;
            }
        printjson(obj);
    })(db,"$DBName","$CollectionName");
"@
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
    function CollectionHasData
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function collectionHasData(adminDB, DBName, collectionName){
    // create results object
    var obj = {
            result: false,
            log: ""
            }
    //switch to collection db
    var db = adminDB.getSiblingDB(DBName);
    // get collection object
    var coll = db.getCollection(collectionName);
    var hasData = coll.find().limit(1).toArray()[0];
            if (hasData == null) {
                    obj.log = "Collection " + DBName + "." + collectionName + " :: has no previous data"
                    obj.result = false;
            } else {
                    obj.log = "Collection " + DBName + "." + collectionName + " :: has previous data"
                    obj.result = true
            }
            printjson(ob7})(db,"$DBName","$CollectionName");
"@  
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
    function RunMongoDBCommand {
        Param(
            [string][Parameter(Mandatory=$True)]$ConnectionString,
            [string][Parameter(Mandatory=$True)]$ScriptJS,
            [Parameter(Mandatory=$True)]$SSHSession
        )
        $FullMongoCommand = "mongo " + $FullMongoURL + "'$ScriptJS'"
            # Run Mongo commands.
            $result = Invoke-SSHCommand -SSHSession $SSHSession -Command $FullMongoCommand -TimeOut 300 -ErrorAction Stop
            # Minimal error handling
            if ($result.ExitStatus -gt 0) {
                    # Closing SSH session
                    Remove-SSHSession $sshSession.SessionId
                    # Throw error when bash or JS fail
                    throw $result.Error + $result.Output
            } else {
            $ReturnObject = $result.Output 
            return $ReturnObject
            }
    }
    
    function IndexExists
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [string][Parameter(Mandatory=$True)]$IndexName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function indexExists(adminDB, DBName, collectionName, indexName) {
            // create results object
                    var obj = {
                    result: false,
                    log: ""
                    }
        
            // change db to the database to query
            var db = adminDB.getSiblingDB(DBName);
            // get all existing collections from the database
            var collection = db.getCollection(collectionName);
            var indexes = collection.getIndexes()
            // loop through all indexes to find the one passed
            for (var i = 0; i < indexes.length; i++) {
                    if (indexes[i].name === indexName) {
                obj.log = "Index :: " + indexName +" has been found"
                            obj.result = true;
                            break;
                    }
            }
        if (!obj.result) 
        {
            obj.log = "Index not found :: " + indexName;
            obj.result = false;
        }
            printjson(obj);
    })(db,"$DBName","$CollectionName","$IndexName");
"@      
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        
        return $found
     }
    
    
     function UpdateShardAndIndexes
     {
            Param(
            [string][Parameter(Mandatory=$True)]$ConnectionString,
            [string][Parameter(Mandatory=$True)]$FullDBName,
            [string][Parameter(Mandatory=$True)]$CollectionName,
            [Parameter(Mandatory=$True)]$DefaultIndex,
            [Parameter(Mandatory=$False)]$DefaultShard,
            [Parameter(Mandatory=$True)]$SSHSession
            )
            
            # Check if collection exists
            Write-Output "Check if collection exists :: $FullDBName.$CollectionName"
            $CollFound = CollectionExists -DBname $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession
            $CollFound.log
            if ($CollFound.result -eq $false) {
                    # Collection not found
                    # Creating collection
                    Write-Output "Creating collection :: $FullDBName.$CollectionName"
                    $NewColl = CreateCollection -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -SSHSession $sshSession
                    $NewColl.log
            }
            # Collection found or created
            
            $idxname = $DefaultIndex.name | ConvertTo-Json -Compress
            $idxjson = $DefaultIndex.key | ConvertTo-Json -Compress
            $Action = $DefaultIndex.action #AddIndex, DropIndex. UpdateIndex, UnShardCollection
    
            # Index Additions
            if($Action -eq "AddIndex"){
    
                    $result = AddIndexes  -FullDBName $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $ConnectionString `
                                            -SSHSession $SSHSession `
                                            -DefaultIndex $DefaultIndex `
                                            -DefaultShard $DefaultShard `
                                            -Action $Action
    
                    $result
            }
    
          #Action is to Drop index
         if($Action -eq "DropIndex"){
                   
                    Write-Output "Index :: " + $idxjson
                    Write-Output "$Options :: " +  $optjson
    
    
                    $Exists = IndexExists -DBname $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession `
                                            -IndexName $idxname.Replace('"',"'") 
                            
    
                    Write-Output "result  :: " + $Exists.result
    
                    if($Exists.result -eq $true)
                    {
                            Write-Output "Dropping index: $idx "
                            $index  = $Indexes | ConvertTo-Json -Compress 
    
                            $DropIndex = DropIndex -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -SSHSession $sshSession `
                                                    -IndexName $idxname.Replace('"',"'")
                                                                                                                    
    
                            $DropIndex.log
                                    
                    } 
                    
            }
    
          #Action is to Update index
         if($Action -eq "UpdateIndex"){                                      
                                    
                    Write-Output "Index :: " + $idxjsonls
                    Write-Output "$Options :: " +  $optjson
    
                    $Exists = IndexExists -DBname $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession `
                                            -IndexName $idxname.Replace('"',"'")                      
    
                    Write-Output "result  :: " + $Exists.result
                    # Drop the index if exists
                    if($Exists.result -eq $true)
                    {
                            Write-Output "Dropping index: $idx "
                            $index  = $Indexes | ConvertTo-Json -Compress 
    
                            $DropIndex = DropIndex -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -SSHSession $sshSession `
                                                    -IndexName $idxname.Replace('"',"'")
    
                            $DropIndex.log
                                    
                    } 
                   
                    #recreate the index with the update
                    $result = AddIndexes  -FullDBName $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $ConnectionString `
                                            -SSHSession $SSHSession `
                                            -DefaultIndex $DefaultIndex `
                                            -DefaultShard $DefaultShard `
                                            -Action $Action
    
                    $result
                    
            }
    
    
            # Shard collection 
            if($Action -eq "UnShardCollection")
            {
                    # Check if Sharded
                    Write-Output "Checking if sharded :: $FullDBName.$CollectionName"
                    $IsCollSharded= IsCollectionSharded -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -SSHSession $sshSession
                    $IsCollSharded.log
                    # If collection is sharded then unshard
                    if($IsCollSharded.result -eq $true) {
                                    
                    # Collection not sharded sharding now 
                    Write-Output "UnSharding collection :: $FullDBName.$CollectionName "
    
                    $ShardedColl = UnshardCollection -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -SSHSession $sshSession
                    $ShardedColl.log
                    }
            }
     }
    
    
     function CreateIndex3
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [Parameter(Mandatory=$True)]$IndexKey,
        [Parameter(Mandatory=$True)]$IndexName,
        [Parameter(Mandatory=$True)]$IndexUnique,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function creatIndex2(adminDB, DBName, collectionName, indexKey, indexName, indexUnique){
            // create results object
            var obj = {
                            result: false,
                            log: "",
                            command: ""
                            }
            //switch to collection db
            var indexCommand = {
                createIndexes : "",
                indexes: [{ key:indexKey,name:indexName, unique:indexUnique}] 
    
            }
    
            indexCommand.createIndexes =collectionName; 
            obj.command = indexCommand;      
    
            var response = adminDB.getSiblingDB(DBName).runCommand(indexCommand);
            obj.log = response        
            printjson(obj)
    })(db,"$DBName","$CollectionName",$IndexKey, "$IndexName", $IndexUnique);
"@
        
        $found = RunMongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
     
    
    function IsCollectionSharded
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function isCollectionSharded(adminDB, DBName, collectionName) {
            // create results object
            var obj = {
                    result: false,
                    log: ""
                    }
            //switch to collection db
            var db = adminDB.getSiblingDB(DBName);
            // get collection object
            var coll = db.getCollection(collectionName);
            if (coll.stats().sharded) {
                    obj.log = "Collection " + DBName + "." + collectionName + " :: is sharded";
                    obj.result = true;
            } else {
                    obj.log = "Collection " + DBName + "." + collectionName + " :: is not sharded";
                    }
            printjson(obj);
    })(db,"$DBName","$CollectionName");
"@
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
    function ShardCollection
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [string][Parameter(Mandatory=$True)]$CollectionName,
        [string][Parameter(Mandatory=$True)]$ShardDetail,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
    (function shardDBCollection(adminDB, DBName, collectionName,ShardDetail){
            print("inside shard collection: " + ShardDetail)
            // create results object
            var obj = {
                    result: false,
                    log: "",
                    command: ""
                    }
            // Shard collection
            var indexCommand = {
                shardCollection : "",
                key: ShardDetail
    
            }
    
            indexCommand.shardCollection = DBName + "." + collectionName
            obj.command = indexCommand;
            var response = adminDB.adminCommand(indexCommand);
    
            if (response.ok === 1) {
                    obj.log = "Collection " + DBName + "." + collectionName +  " :: has been sharded";
                    obj.result = true;
            } else {
                    obj.log = response.errmsg
                    }
            printjson(obj);
    })(db,"$DBName","$CollectionName", $ShardDetail);
"@
        $found = RunMongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
    function DropDatabase
     {
        Param(
        [string][Parameter(Mandatory=$True)]$ConnectionString,
        [string][Parameter(Mandatory=$True)]$DBName,
        [Parameter(Mandatory=$True)]$SSHSession
        )
        $ScriptJs = @"
        (function dropDatabase(adminDB, DBName){
            // create results object
            var obj = {
                    result: false,
                    log: ""
                    }
            //switch to db
            var db = adminDB.getSiblingDB(DBName);
            // Drop database
            if (db.getName() != "admin" && db.getName() != "config") {
                    var response = db.dropDatabase();
            } else {
                    var response = {};
                    response.errmsg = "Cannot delete:: " + db;
            }
            if (response.ok === 1) {
                    obj.log = "Database " + DBName + " :: has been dropped";
                    obj.result = true;
            } else {
                    obj.log = response.errmsg
                    }
            printjson(obj);
    })(db,"$DBName");
"@
        $found = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
        return $found
     }
    
     function DropIndex
     {
            Param(
                    [string][Parameter(Mandatory=$True)]$ConnectionString,
                    [string][Parameter(Mandatory=$True)]$DBName,
                    [string][Parameter(Mandatory=$True)]$CollectionName,
                    [Parameter(Mandatory=$True)]$IndexName,
                    [Parameter(Mandatory=$True)]$SSHSession
                    )
                    $ScriptJs = @"
    (function DropIndex(adminDB, DBName, collectionName, indexName){
            // create results object
            var obj = {
                            result: false,
                            log: "",
                            command: ""
                            }
            //switch to collection db
            var indexCommand = {
            dropIndexes : "",
            index: "" 
    
            }
    
            indexCommand.dropIndexes =collectionName; 
            indexCommand.index = indexName;
            obj.command = indexCommand;      
    
            var response = adminDB.getSiblingDB(DBName).runCommand(indexCommand);
            obj.log = response        
            printjson(obj)
    })(db,"$DBName","$CollectionName","$IndexName");
"@
             $result = RunMongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
             return $result    
    }
    
    
    function AddIndexes{
    Param(
    [string][Parameter(Mandatory=$True)]$ConnectionString,
    [string][Parameter(Mandatory=$True)]$FullDBName,
    [string][Parameter(Mandatory=$True)]$CollectionName,
    [Parameter(Mandatory=$True)]$DefaultIndex,
    [Parameter(Mandatory=$False)]$DefaultShard,
    [Parameter(Mandatory=$True)]$SSHSession,
    [Parameter(Mandatory=$False)]$Action
    )
            # create all indexes if specified      
            foreach($idx in ($DefaultIndex))
            {                        
                    $indexkey = $idx.key | ConvertTo-Json -Compress
                    $indexUnique = $idx.unique | ConvertTo-Json -Compress
                    $idxname = $idx.name | ConvertTo-Json -Compress
                    $idxjson = $idx | ConvertTo-Json -Compress
                            
                                    
                    Write-Output "Index :: " + $idxjson
                    Write-Output "$Options :: " +  $optjson
    
    
                    $Exists = IndexExists -DBname $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession `
                                            -IndexName $idxname.Replace('"',"'") 
                            
    
                    Write-Output "result  :: " + $Exists.result
    
                    if($Exists.result -ne $true)
                    {
                    Write-Output "Creating index: $idx "
                    $index  = $Indexes | ConvertTo-Json -Compress 
    
                    $NewIndex = CreateIndex3 -DBname $FullDBName `
                                            -CollectionName $CollectionName `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession `
                                            -IndexKey $indexkey.Replace('"',"") `
                                            -IndexName $idxname.Replace('"',"'") `
                                            -IndexUnique $indexUnique.Replace('"',"")
                                                                                                            
    
                    $NewIndex.log
                                    
                    }
    
                                    
            } 
                            
    
            # Shard collection 
            if($DefaultShard -ne $null)
            {
                    $ShardDetail = $DefaultShard | ConvertTo-Json
    
                    # Check if Sharded
                    Write-Output "Checking if sharded :: $FullDBName.$CollectionName"
                    $IsCollSharded= IsCollectionSharded -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -SSHSession $sshSession
                    $IsCollSharded.log
                    # If not sharded check if collection has data
                    if($IsCollSharded.result -eq $false) {
                                    
                    # Collection not sharded sharding now 
                    Write-Output "Sharding collection :: $FullDBName.$CollectionName with details :: $ShardDetail"
    
                    $ShardedColl = ShardCollection -DBname $FullDBName `
                                                    -CollectionName $CollectionName `
                                                    -ConnectionString $FullMongoURL `
                                                    -ShardDetail $ShardDetail `
                                                    -SSHSession $sshSession
                    $ShardedColl.log
                    }
            }
    }
    
    
    function UnshardCollection
    {
       Param(
       [string][Parameter(Mandatory=$True)]$ConnectionString,
       [string][Parameter(Mandatory=$True)]$DBName,
       [string][Parameter(Mandatory=$True)]$CollectionName,
       [Parameter(Mandatory=$True)]$SSHSession
       )
       $ScriptJs = @"
    (function unshardCollection(adminDB, DBName, collectionName){
        // create results object
        var obj = {
                        result: false,
                        log: ""
        }

        //switch to collection db
        var db = adminDB.getSiblingDB(DBName);

        // get collection object
        var coll = db.getCollection(collectionName);
        var collectionFullName = DBName + "." + collectionName;

        sh.stopBalancer();

        // switch to config db
        var configDB = adminDB.getSiblingDB("config");

        var primary = configDB.databases.findOne({_id: DBName}).primary;

        // move all chunks to primary
        coll.find({ns: collectionFullName, shard: {"`$ne": primary}}).forEach(function(chunk){
                        sh.moveChunk(collectionFullName, chunk.min, primary);
        });

        // unshard
        configDB.collections.remove({ "_id" : collectionFullName });
        coll.remove({ ns : collectionFullName });
        
        adminDB.runCommand({ flushRouterConfig: 1 });

        sh.startBalancer()

})(db,"$DBName","$CollectionName");
"@  
       $result = MongoDBCommand -ConnectionString $ConnectionString -SCriptJS $ScriptJS -SSHSession $sshSession
       return $result
    }
        