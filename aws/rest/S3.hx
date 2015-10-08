package aws.rest;

import haxe.xml.Fast;

using StringTools;


/**  File system operations for use with
  *  AWS S3 REST interface.
 **/

class S3 extends AWS {

  private function signAndSendRequest(method : String) {
    var post = false;

    if (method == "PUT" || method == "POST") {
      post = true;
    }

    var bytesOutput = new haxe.io.BytesOutput();
    this.sigV4request.applySigning(method);
    this.sigV4request.customRequest(post, bytesOutput, method);
    this.response = bytesOutput.getBytes().toString();

    if (this.response.indexOf("<Error>") >= 0) {
      var awsError = new AWSError(this.response);
      throw awsError;
    }
  }

  private function normalizePath (path : String) : String {
    var pathTrim = path.trim();

    if (pathTrim.startsWith("/")) {
      pathTrim = pathTrim.substring(1, pathTrim.length);
    }

    if (pathTrim.endsWith("/")) {
      pathTrim = pathTrim.substring(0, pathTrim.length-1);
    }

    return pathTrim;
  }

  public function createBucket(name : String, region : String){
    this.setEndpoint(this.normalizePath(name));
    this.sigV4request.setPostData('<CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><LocationConstraint>' + region + '</LocationConstraint></CreateBucketConfiguration>');
    this.signAndSendRequest("PUT");
  }

  // Careful: Only lists the first 1000 objects!
  // TODO: check 'truncate' flag to see if there are still more files
  public function listFilesInDir(bucket : String, path : String) : Array<String> {
    this.setEndpoint(this.normalizePath(bucket));
    var prefix = this.normalizePath(path) + "/";
    this.sigV4request.setParameter("prefix", prefix);
    this.signAndSendRequest("GET");

    var xml = Xml.parse(this.response);
    var fast = new Fast(xml.firstElement());
    var files = new Array<String>();

    for (content in fast.nodes.Contents) {
      files.push(content.node.Key.innerData.replace(prefix, ""));
    }

    // Delete folder entry
    files.remove("");
    return files;
  }

  public function sendFile(bucket : String, path : String) {
    this.setEndpoint(this.normalizePath(bucket), this.normalizePath(path));
    this.signAndSendRequest("GET");
  }

  public function addFile(bucket : String, path : String) {
    this.setEndpoint(this.normalizePath(bucket), this.normalizePath(path));
    this.sigV4request.setPostData(php.Web.getPostData());
    this.signAndSendRequest("GET");
  }

  public function delFile(bucket : String, path : String) {
    this.setEndpoint(this.normalizePath(bucket), this.normalizePath(path));
    this.signAndSendRequest("DELETE");
  }

  // Can delete up to 1000 objects at once
  public function recursiveDeleteDirectory(bucket : String, path : String) {
    var normalizedBucket = this.normalizePath(bucket);
    var normalizedPath = this.normalizePath(path);

    var files = this.listFilesInDir(normalizedBucket, normalizedPath);

    this.setEndpoint(normalizedBucket);
    var prefix = normalizedPath + "/";

    var deleteXml = Xml.createElement("Delete");

    for (file in files) {
      var object = Xml.createElement("Object");
      deleteXml.addChild(object);

      var key = Xml.createElement("Key");
      object.addChild(key);
      key.addChild(Xml.createPCData(prefix + file));
    }

    // Parameters in POST requests are not resolved in the URI by Http class.
    // However, we still need the delete parameter, which we set manually in Sig4Http
    // when the delete paramter was set like this:
    this.sigV4request.setParameter("delete", "");
    this.sigV4request.setPostData(deleteXml.toString());
    this.signAndSendRequest("POST");
  }
}
