//
//  APICore.swift
//  RestAPICaller
//
//  Created by Steven Yang on 12/22/21.
//

import Foundation
import os.log

struct HTTPHeader {
    let key: String
    let value: String
}

enum HTTPStatusCode: Int {
    // 2XXs - Success
    case OK = 200
    case Created = 201
    case Accepted = 202
    case NoContent = 204

    // 4XXs - Client Errors
    case BadRequest = 400
    case Unauthorized = 401
    case Forbidden = 403
    case NotFound = 404
    case MethodNotAllowed = 405
    case NotAcceptable = 406
    case RequestTimeout = 408
    case UnprocessableEntity =  422

    // 5XXs - Server Errors
    case InternalServerError = 500
    case NotImplemented = 501
    case BadGateway = 502
    case ServiceUnavailable = 503
    case GatewayTimeout = 504
}

/// HTTPMethod for a APICore request
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case head = "HEAD"
    case patch = "PATCH"
}

enum ContentType: String {
    case json = "application/json"
}

/// Types of API errors
enum APIError: Error {
    case error(Error)
    case invalidRequestPayload
    case invalidQueryParams
    case invalidURLResponse
    case invalidHTTPStatusCode(statusCode: Int, reason: String?)
    case noData
    case expectingNoData
    case jsonDecoding(Error)

    var localizedDescription: String {
        switch self {
        case let .invalidHTTPStatusCode(statusCode, reason):
            return "APIError.invalidHTTPStatusCode(statusCode: \(statusCode), reason: \(reason ?? "--")"
        case let .jsonDecoding(jsonError):
            return "APIError.jsonDecoding(\(jsonError.localizedDescription)"
        case .noData:
            return "APIError.noData"
        case .invalidRequestPayload:
            return "APIError.invalidRequestPayload"
        case .expectingNoData:
            return "APIError.expectingNoData"
        case let .error(error):
            return "APIError.error(\(error.localizedDescription)"
        case .invalidURLResponse:
            return "APIError.invalidURLResponse"
        case .invalidQueryParams:
            return "APIError.invalidQueryParams"
        }
    }
}

/// type to use when no HTTPBoddy in the request is expected
struct APIEmptyRequestBody: Encodable { }

/// type to use when no server reply is expected
struct APIEmptyResult: Decodable { }

/// APICore - all APIs should conform to this protocol
protocol APICore {
    /// the type of any supplied HTTPBody, or APIEmptyRequestBody if no HTTPBody is required
    associatedtype APIRequestBody: Encodable

    /// the type of any expected API response, or APIEmptyResult if no API result tpye is expected
    associatedtype APIResult: Decodable

    /// path component for the particular API endpoint
    static var pathComponent: String { get }

    /// full URL to the API endpoint
    static var url: URL { get }
    
    /// Utility method to create a URLRequest from given parameters
    /// - Parameters:
    ///   - url: URL for the request
    ///   - httpMethod: HTTPMethod for the request.
    ///   - httpHeaders: optional array of HTTPHeader for the request
    ///   - httpBody: optional APIRequestBody for the request
    ///   - urlQueryItems: optional array of URLQueryItem
    /// - returns: URLRequest built from the supplied parameters
    func createURLRequest(url: URL,
                          httpMethod: HTTPMethod,
                          httpHeaders: [HTTPHeader]?,
                          httpBody: APIRequestBody?,
                          urlQueryItems: [URLQueryItem]?) -> URLRequest
    
    /// APICore request  is the main entrypoint for creating and executing an HTTP request
    /// - Parameters:
    ///   - urlSession: URLSession for creating a task in order to execute the request. Defaults to URLSession.shared
    ///   - url: URL for the request
    ///   - httpMethod: HTTPMethod for the request. Defaults to "GET"
    ///   - httpHeaders: optional HTTPHeaders for the request
    ///   - httpBody: optional HTTPBody for the request
    ///   - urlQueryItems: optional array of APIRequestBody for the request
    ///   - httpStatusCode: HTTPStatusCode used to determine if a successful response was  received. Defaults to HTTPStatusCode.OK
    ///   - completion: escaping completion handler returning a Result<APIResult, APIError>
    func request(urlSession: URLSession,
                 url: URL,
                 httpMethod: HTTPMethod,
                 httpHeaders: [HTTPHeader]?,
                 httpBody: APIRequestBody?,
                 urlQueryItems: [URLQueryItem]?,
                 httpStatusCode: HTTPStatusCode,
                 completion: @escaping (Result<APIResult, APIError>) -> Void)
    
    /// APICore request  is the main entrypoint for creating and executing an HTTP request
    /// - Parameters:
    ///   - urlSession: URLSession for creating a task in order to execute the request. Defaults to URLSession.shared
    ///   - urlRequest: URLRequest to execute
    ///   - httpStatusCode: HTTPStatusCode used to determine if a successful response was  received. Defaults to HTTPStatusCode.OK
    ///   - completion: escaping completion handler returning a Result<APIResult, APIError>
    func request(urlSession: URLSession,
                 urlRequest: URLRequest,
                 httpStatusCode: HTTPStatusCode,
                 completion: @escaping (Result<APIResult, APIError>) -> Void)
}

extension APICore {
    func createURLRequest(url: URL,
                          httpMethod: HTTPMethod = HTTPMethod.get,
                          httpHeaders: [HTTPHeader]? = nil,
                          httpBody: APIRequestBody? = nil,
                          urlQueryItems: [URLQueryItem]? = nil) -> URLRequest {
        
        var urlRequest = URLRequest(url: url)
        
        // add urlQueryItems if supplied
        if urlQueryItems != nil, var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            urlComponents.queryItems = urlQueryItems
            if let url = urlComponents.url {
                urlRequest = URLRequest(url: url)
            }
        }
        
        urlRequest.httpMethod = httpMethod.rawValue
        
        // add default JSON Accept header
        urlRequest.addValue(ContentType.json.rawValue, forHTTPHeaderField: "Accept")
        
        // add any additional headers
        httpHeaders?.forEach { urlRequest.addValue($0.value, forHTTPHeaderField: $0.key) }
        
        // add Content-Type header and encoded httpBody if supplied
        if let httpBody = httpBody {
            urlRequest.addValue(ContentType.json.rawValue, forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            urlRequest.httpBody = try? encoder.encode(httpBody)
            if let data = urlRequest.httpBody, let jsonString = String(data: data, encoding: .utf8) {
                os_log("*** APIRequest:\n%@\nhttpBody:\n%@", log: .default, type: .debug, urlRequest.debugDescription, jsonString)
            }
        }

        return urlRequest
    }
    
    func request(urlSession: URLSession = URLSession.shared,
                 url: URL,
                 httpMethod: HTTPMethod = HTTPMethod.get,
                 httpHeaders: [HTTPHeader]? = nil,
                 httpBody: APIRequestBody? = nil,
                 urlQueryItems: [URLQueryItem]? = nil,
                 httpStatusCode: HTTPStatusCode = HTTPStatusCode.OK,
                 completion: @escaping (Result<APIResult, APIError>) -> Void) {
        
        // build request
        let urlRequest = createURLRequest(url: url,
                                          httpMethod: httpMethod,
                                          httpHeaders: httpHeaders,
                                          httpBody: httpBody,
                                          urlQueryItems: urlQueryItems)
        request(urlSession: urlSession, urlRequest: urlRequest, httpStatusCode: httpStatusCode, completion: completion)
    }
    
    func request(urlSession: URLSession = URLSession.shared,
                 urlRequest: URLRequest,
                 httpStatusCode: HTTPStatusCode = HTTPStatusCode.OK,
                 completion: @escaping (Result<APIResult, APIError>) -> Void) {

        urlSession.dataTask(with: urlRequest) { data, urlResponse, error in
            
            var result: Result<APIResult, APIError>?
            
            // verify no error, urlResponse is HTTPURLResponse, and expected HTTPStatusCode
            if let error = error {
                if let error = error as? APIError {
                    result = .failure(error)
                } else {
                    result = .failure(APIError.error(error))
                }
            } else if urlResponse as? HTTPURLResponse == nil {
                result = .failure(APIError.invalidURLResponse)
            } else if let httpURLResponse = urlResponse as? HTTPURLResponse {
                if httpURLResponse.statusCode != httpStatusCode.rawValue {
                    let apiError = APIError.invalidHTTPStatusCode(statusCode: httpURLResponse.statusCode, reason: httpURLResponse.description)
                    result = .failure(apiError)
                }
            }
            
            // process response and verify expected results
            if result == nil {
                if APIResult.self is APIEmptyResult.Type { // APIEmptyResult expected?
                    if data == nil {
                        result = .success(APIEmptyResult() as! APIResult)
                    } else {
                        result = .failure(APIError.expectingNoData)
                    }
                } else if let data = data { // expecting data
                    do {
                        let apiResult = try JSONDecoder().decode(APIResult.self, from: data)
                        result = .success(apiResult)
                    } catch {
                        // try to log UTF-8 of what was returned for data when JSON didn't parse!
                        if let invalidJSONString = String(data: data, encoding: .utf8) {
                            os_log("*** APIError.jsonDecoding: invalid JSON response ***\n%@", log: .default, type: .error, invalidJSONString)
                        }
                        result = .failure(APIError.jsonDecoding(error))
                    }
                } else {
                    result = .failure(APIError.noData)
                }
            }
            
            if case let .failure(apiError) = result {
                self.logAPIError(apiError, for: urlRequest)
            }
            
            if let result = result {
                completion(result)
            }

        }.resume()
    }
    
    /// Utility function to log various kinds of APIErrors
    /// - Parameters:
    ///   - apiError: APIError to log
    ///   - urlRequest: URLRequest that failed with an APIError
    func logAPIError(_ apiError: APIError, for urlRequest: URLRequest) {
        let urlRequestString = String(describing: urlRequest.url?.absoluteString)
        os_log("URLRequest: %@: %@", log: .default, type: .error, urlRequestString, apiError.localizedDescription)
    }

}


