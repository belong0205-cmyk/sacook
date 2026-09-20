#import "SCProfileDocument.h"
static NSError *SCProfileError(NSString *message) { return [NSError errorWithDomain:@"SA Cook Profile" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; }
// Read only: no files are extracted to disk. Bound stdout and execution time
// even for corrupt archives or a compressed document with an excessive size.
static NSData *SCReadZipOutput(NSArray<NSString *> *arguments, NSUInteger limit) {
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/unzip"]; task.arguments=arguments;
    task.currentDirectoryURL=[NSURL fileURLWithPath:@"/private/tmp"];
    NSPipe *pipe=[NSPipe pipe]; task.standardOutput=pipe; task.standardError=[NSFileHandle fileHandleWithNullDevice]; task.standardInput=[NSFileHandle fileHandleWithNullDevice];
    if(![task launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{ if(task.running) [task terminate]; });
    NSMutableData *result=[NSMutableData data]; BOOL exceeded=NO;
    for(;;) { NSData *chunk=[pipe.fileHandleForReading availableData]; if(!chunk.length) break; if(result.length+chunk.length>limit) { exceeded=YES; [task terminate]; break; } [result appendData:chunk]; }
    [pipe.fileHandleForReading closeFile]; [task waitUntilExit];
    return !exceeded && task.terminationStatus==0?result:nil;
}
@interface SCWordTextParser : NSObject <NSXMLParserDelegate>
@property NSMutableString *text;
@property NSUInteger depth;
@property NSUInteger excludedDepth;
@property BOOL inText;
@property BOOL exceeded;
@end
@implementation SCWordTextParser
- (void)add:(NSString *)text parser:(NSXMLParser *)parser {
    if(self.text.length+text.length>40000) { self.exceeded=YES; [parser abortParsing]; return; }
    [self.text appendString:text];
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified attributes:(NSDictionary *)attributes {
    if(++self.depth>150) { self.exceeded=YES; [parser abortParsing]; return; }
    if(self.excludedDepth) { self.excludedDepth++; return; }
    if(![uri isEqual:@"http://schemas.openxmlformats.org/wordprocessingml/2006/main"] && ![uri isEqual:@"http://purl.oclc.org/ooxml/wordprocessingml/main"]) return;
    if([@[@"del",@"moveFrom",@"instrText"] containsObject:name]) { self.excludedDepth=1; return; }
    if([name isEqual:@"t"]) self.inText=YES;
    if([name isEqual:@"tab"]) [self add:@"\t" parser:parser];
    if([@[@"br",@"cr"] containsObject:name]) [self add:@"\n" parser:parser];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string { if(self.inText && !self.excludedDepth) [self add:string parser:parser]; }
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {
    if(self.depth) self.depth--;
    if(self.excludedDepth) { self.excludedDepth--; return; }
    if(![uri isEqual:@"http://schemas.openxmlformats.org/wordprocessingml/2006/main"] && ![uri isEqual:@"http://purl.oclc.org/ooxml/wordprocessingml/main"]) return;
    if([name isEqual:@"t"]) self.inText=NO;
    if([@[@"p",@"tr"] containsObject:name]) [self add:@"\n" parser:parser];
    if([name isEqual:@"tc"]) [self add:@"\t" parser:parser];
}
@end
NSString *SCReadProfileDocument(NSURL *url, NSError **error) {
    NSNumber *size; [url getResourceValue:&size forKey:NSURLFileSizeKey error:error];
    if(!size || size.unsignedLongLongValue>10*1024*1024 || size.unsignedLongLongValue==0) { if(error)*error=SCProfileError(@"Hãy chọn file không rỗng, nhỏ hơn 10 MB."); return nil; }
    NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error]; if(!data) return nil;
    NSString *extension=url.pathExtension.lowercaseString;
    if([@[@"txt",@"md"] containsObject:extension]) {
      NSString *text=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if(!text.length || text.length>40000) { if(error)*error=SCProfileError(@"Văn bản cần là UTF-8, không rỗng và tối đa 40.000 ký tự."); return nil; } return text;
    }
    if(![extension isEqual:@"docx"]) { if(error)*error=SCProfileError(@"Hãy lưu Word thành .docx hoặc dán nội dung vào ô nhập."); return nil; }
    NSMutableDictionary *parts=[NSMutableDictionary dictionary]; NSString *failure=nil;
    NSData *listing=SCReadZipOutput(@[@"-Z1",url.path],256*1024);
    NSString *names=listing?[[NSString alloc] initWithData:listing encoding:NSUTF8StringEncoding]:nil;
    NSArray *entries=[names componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if(!names.length || entries.count>2000) failure=@"Không đọc được Word. File cần là .docx không có mật khẩu, tối đa 2.000 thành phần.";
    NSUInteger total=0;
    for(NSString *path in entries) {
      if(failure) break;
      if([path rangeOfString:@"^word/(document|header[0-9]+|footer[0-9]+)\\.xml$" options:NSRegularExpressionSearch].location==NSNotFound) continue;
      if(parts[path] || parts.count>=24) { failure=@"File Word bị trùng hoặc chứa quá nhiều phần văn bản."; break; }
      NSData *xml=SCReadZipOutput(@[@"-p",url.path,path],2*1024*1024); total+=xml.length;
      if(!xml || total>12*1024*1024) { failure=@"Nội dung Word bị hỏng, quá lớn hoặc có mật khẩu."; break; }
      NSString *decoded=[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:xml encoding:NSUTF16StringEncoding];
      if(!decoded || [decoded rangeOfString:@"<!DOCTYPE|<!ENTITY" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound) { failure=@"File Word có XML không được hỗ trợ."; break; }
      SCWordTextParser *reader=[SCWordTextParser new]; reader.text=[NSMutableString string];
      NSXMLParser *parser=[[NSXMLParser alloc] initWithData:xml]; parser.delegate=reader; parser.shouldProcessNamespaces=YES; parser.shouldResolveExternalEntities=NO;
      if(![parser parse]) { failure=reader.exceeded?@"Nội dung vượt giới hạn. Hãy chia nhỏ file.":@"XML trong file Word không hợp lệ."; break; }
      parts[path]=[reader.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    if(!failure && !parts[@"word/document.xml"]) failure=@"File không chứa tài liệu Word hợp lệ.";
    NSMutableArray *texts=[NSMutableArray array]; if(parts[@"word/document.xml"]) [texts addObject:parts[@"word/document.xml"]];
    for(NSString *key in [parts.allKeys sortedArrayUsingSelector:@selector(compare:)]) if(![key isEqual:@"word/document.xml"]) [texts addObject:parts[key]];
    NSString *text=[[texts componentsJoinedByString:@"\n\n"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!failure && (!text.length || text.length>40000)) failure=text.length?@"Nội dung vượt quá 40.000 ký tự. Hãy chia nhỏ file.":@"Không tìm thấy chữ. File chỉ có ảnh cần chuyển thành văn bản trước.";
    if(failure) { if(error)*error=SCProfileError(failure); return nil; }
    return text;
}
