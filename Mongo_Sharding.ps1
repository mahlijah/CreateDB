#++++++++++++++++++++++++++++++++++
#  Variables
#++++++++++++++++++++++++++++++++++
$PassWord = "pwd"
$UserName = "user"
$Orchestrator = "sm-az-useast.test.com"


#++++++++++++++++++++++++++++++++++
#  Create Credential
#++++++++++++++++++++++++++++++++++
$vmSecurePassword = ConvertTo-SecureString $PassWord -AsPlainText -Force
$vmCredential = New-Object System.Management.Automation.PSCredential ($UserName, $vmSecurePassword);

#++++++++++++++++++++++++++++++++++
#  Create SSH Session.
#++++++++++++++++++++++++++++++++++
$sshSession = New-SSHSession -ComputerName $Orchestrator -Credential $vmCredential -ConnectionTimeout 30

#++++++++++++++++++++++++++++++++++
#  Import functions module.
#++++++++++++++++++++++++++++++++++
Import-Module .\Mongo_Manage.psm1 -force

#++++++++++++++++++++++++++++++++++
#  DBname Suffix needs to be passed
#++++++++++++++++++++++++++++++++++
$Suffix = 'QA01'

#++++++++++++++++++++++++++++++++++
# Mongo Variables
#++++++++++++++++++++++++++++++++++
$MongoDBPrefix = 'mongodb://'
$MongoDBUserName = 'user'
$MongoDBPassword = 'pwd'
$MongoSHost = 'sm-az-useast'
$MongoSPort = '27017'
$MongoAuthDB = 'admin' 
$IntegratedSecurity = $false
$MongoParams = " --quiet --eval "
$UseSSHConnection = $true

#++++++++++++++++++++++++++++++++++
#  Load JSON File with DBCollections
#++++++++++++++++++++++++++++++++++
$PathToJsonFile = '.\DBObjects.json'
$JSON = get-content -Raw -path $PathToJsonFile -ErrorAction Stop | ConvertFrom-Json 

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# Run through the json
# Create and Shard DBs / Collections
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
$FullMongoURL = MongoConnectionString -MongoDBPrefix $MongoDBPrefix `
                                      -MongoSHost $MongoSHost `
                                      -MongoDBPassword $MongoDBPassword `
                                      -MongoDBUserName $MongoDBUserName `
                                      -MongoSPort $MongoSPort `
                                      -MongoAuthDB $MongoAuthDB `
                                      -IntegratedSecurity $IntegratedSecurity `
                                      -MongoParams $MongoParams


#$FullMongoURL = 'mongodb://AhlijahM-o790-10:27017'

foreach ($Item in $JSON) {
   $FullDBName = $item.name + '_' + $Suffix
   Write-Output "Searching for DB :: $FullDBName"
   $DBFound = DBExists -DBname $FullDBName `
                       -ConnectionString $FullMongoURL `
                       -SSHSession $sshSession
  
   Write-Output $DBFound.log
   Write-Output "Checking Sharding status for DB :: $FullDBName"
   $DBSharded = ISDBSharded -DBname $FullDBName `
                            -ConnectionString $FullMongoURL `
                            -SSHSession $sshSession
   
   Write-Output $DBSharded.log
   # Find if DB is sharded. A database could be sharded ever when not found.
   if ($DBSharded.result -eq $false) {
        # DB is not sharded sharding now 
        $ShardedDB = ShardDB -DBname $FullDBName `
                             -ConnectionString $FullMongoURL `
                             -SSHSession $sshSession
        $ShardedDB.log
   }

   # Create Collections
   foreach ($collection in ($Item.collections.PSObject.Members | Where-Object { $_.MemberType -eq 'NoteProperty'})) {
        $Coll =  $collection.Name
        $CollValue = $collection.Value

        #for default , create the default shard for all other collections not listed.
        #default Sharding at this time is Company 
        $Index = $CollValue.Indexes
        $Shard = $CollValue.ShardKey
        

        if($Coll -eq "Default")
        {
            $defaultCollections = $CollValue.DefaultCollections
            foreach($col in $defaultCollections){

            UpdateShardAndIndexes -FullDBName $FullDBName `
                                            -CollectionName $col `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession `
                                            -DefaultIndex $Index `
                                            -DefaultShard $Shard
            }
    
        }
        else
        {
			$indexes = $CollValue.Indexes
            foreach($index in $indexes){							 
										
                UpdateShardAndIndexes -FullDBName $FullDBName `
                                            -CollectionName $Coll `
                                            -ConnectionString $FullMongoURL `
                                            -SSHSession $sshSession `
                                            -DefaultIndex $Index `
                                            -DefaultShard $Shard

			   } 
        }
    } 
}
#>   

<#foreach ($Item in $JSON) {
   $FullDBName = $item.name + '_' + $Suffix
   Write-Output "Deleting DB :: $FullDBName"
   $DroppedDB = DropDatabase -ConnectionString $FullMongoURL `
                             -DBName $FullDBname `
                             -SSHSession $sshSession
   Write-Output $DroppedDB.log
}
#>

#++++++++++++++++++++++++++++++++++
#  Remover SSH/sftp Session.
#++++++++++++++++++++++++++++++++++
Remove-SSHSession $sshSession.SessionId
