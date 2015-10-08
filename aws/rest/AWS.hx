package aws.rest;


/**  AWS base class. All services should
  *  extend this class.
 **/

class AWS {

  var sigV4request : SigV4;
  var response : String;

  public function new(awsHost : String, awsAccessKey : String, awsSecretKey : String, awsRegion : String,
                      awsService : String, object : String) {
    this.sigV4request = new SigV4(awsHost, awsAccessKey, awsSecretKey, awsRegion, awsService, object);
  }

  private function setEndpoint(awsHost : String, object = "") {
    var awsHost = awsHost + "." + this.sigV4request.awsHost;
    var endpoint = this.sigV4request.setEndpoint(awsHost, object);
    this.sigV4request.url = endpoint;
  }
}