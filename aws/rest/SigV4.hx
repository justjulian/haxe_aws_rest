// Copyright (C) 2013 Sam MacPherson

package aws.rest;

import haxe.crypto.Base64;
import haxe.crypto.Hmac;
import haxe.crypto.Sha256;
import haxe.crypto.Md5;
import haxe.Http;
import haxe.io.Bytes;

using DateTools;
using StringTools;


/**
 * Extends haxe.Http to sign the request using AWS IAM Sig V4 before sending.
 * Signature format gathered from here:
 * http://docs.amazonwebservices.com/general/latest/gr/sigv4-create-canonical-request.html
 */

class SigV4 extends Http {

  public var awsHost : String;
  var awsAccessKey : String;
  var awsSecretKey : String;
  var awsRegion : String;
  var awsService : String;
  var signParams = new Array<{param : String, value : String}>();
  var bodyData : String;
  var canonicalUri : String;

  /**
   * Creates a new http connection with Signature V4 authentication.
   */
  public function new(awsHost : String, awsAccessKey : String, awsSecretKey : String, awsRegion : String,
                      awsService : String, object : String) {
    this.awsAccessKey = awsAccessKey;
    this.awsSecretKey = awsSecretKey;
    this.awsRegion = awsRegion;
    this.awsService = awsService;
    this.bodyData = "";
    var endpoint = this.setEndpoint(awsHost, object);

    super(endpoint);
  }

  public function setEndpoint(awsHost : String, object : String) : String {
    this.awsHost = awsHost;
    this.canonicalUri = "/" + object;

    // TODO enable https (getting error back so far when using https)
    var endpoint = "http://" + this.awsHost + this.canonicalUri;

    return endpoint;
  }

  public override function setPostData(data : String) : Http {
    super.setPostData(data);
    this.bodyData = data;

    return this;
  }

  public override function setParameter(param : String, value : String) : Http {
    super.setParameter(param, value);

    // Add in the parameter for future signing
    signParams.push({param : param.urlEncode(), value : value.urlEncode()});

    return this;
  }

  /**
   * Adds a signature header to the http query. Call this method before to submit the request.
   *
   * @param	method	Specify method for request.
   * @author Sam MacPherson
   */
  public function applySigning(method : String) : Void {
    var now = Date.now();
    var amzdate = now.format("%Y%m%dT%H%M%SZ");
    var datestamp = now.format("%Y%m%d");

    var canonicalUri = this.canonicalUri;

    this.signParams.sort(function (x, y) : Int {
      return x.param > y.param ? 1 : -1;
    });

    var canonicalQuerystring = "";

    if (signParams.length >= 1) {
      if (signParams[0].param == "delete" && signParams[0].value == "") {
        canonicalQuerystring = "delete=";
        this.url += "?" + canonicalQuerystring;
      } else {
        for (i in 0 ... signParams.length) {
          var entry = signParams[i];
          canonicalQuerystring += entry.param + "=" + entry.value;

          if (i + 1 < signParams.length) {
            canonicalQuerystring += "&";
          }
        }
      }
    }

    var canonicalHeadersPost = "";
    var signedHeadersPost = "";

    if (method == "PUT" || method == "POST") {
     // Add content-md5
      var contentMD5 = Base64.encode(Md5.make(Bytes.ofString(this.bodyData)));
      canonicalHeadersPost = "content-md5:" + contentMD5 + "\n";
      signedHeadersPost = "content-md5;";
      setHeader("Content-MD5", contentMD5);

      // Add other POST headers here if necessary (take care of order!)
    }

    var canonicalHeaders = canonicalHeadersPost + "host:" + this.awsHost + "\n" + "x-amz-date:" + amzdate + "\n";
    var signedHeaders = signedHeadersPost + "host;x-amz-date";
    var payloadHash = Sha256.encode(this.bodyData);
    var canonicalRequest = method + "\n" + this.canonicalUri + "\n" + canonicalQuerystring + "\n" +
                           canonicalHeaders + "\n" + signedHeaders + "\n" + payloadHash;
    var credentialScope = datestamp + "/" + this.awsRegion + "/" + this.awsService + "/" + "aws4_request";
    var algorithm = "AWS4-HMAC-SHA256";
    var stringToSign = algorithm + "\n" +  amzdate + "\n" +  credentialScope + "\n" +  Sha256.encode(canonicalRequest);

    var hmac = new Hmac(SHA256);
    var signingKey = hmac.make(hmac.make(hmac.make(hmac.make(Bytes.ofString("AWS4" + this.awsSecretKey),
                                                             Bytes.ofString(datestamp)),
                                                   Bytes.ofString(this.awsRegion)),
                                         Bytes.ofString(this.awsService)),
                               Bytes.ofString("aws4_request"));
    var signature = hmac.make(signingKey, Bytes.ofString(stringToSign)).toHex();

    var authorizationHeader = algorithm + " " + "Credential=" + this.awsAccessKey + "/" + credentialScope + ", " +
                              "SignedHeaders=" + signedHeaders + ", " + "Signature=" + signature;

    setHeader("Authorization", authorizationHeader);
    setHeader("x-amz-date", amzdate);
    setHeader("x-amz-content-sha256", payloadHash);
  }
}