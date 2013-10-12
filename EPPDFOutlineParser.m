//
//  EPPDFOutlineParser.m
//  EPPDFOutlineParsing
//
//  Created by EXphinx on 11-6-13.
//  Copyright (c) 2011年 EXphinx. All rights reserved.
//

#import "EPPDFOutlineParser.h"

@interface EPPDFOutlineParser ()
@property (nonatomic, strong) NSArray *outlineItems;
@property (nonatomic, strong) NSDictionary *pageDataDictionary;
@property (nonatomic, strong) NSArray *pageIndexData;
@end

@interface EPPDFOutlineItem ()
+ (instancetype)item;
@property (nonatomic, strong) NSMutableArray *childrenItems;
- (void)addChildItem:(EPPDFOutlineItem *)childItem;
@end

@implementation EPPDFOutlineParser {
    CGPDFDocumentRef _document;
    CGPDFDictionaryRef _destDic;
    dispatch_queue_t _parsingQueue;
}

- (id)initWithPDFDocument:(CGPDFDocumentRef)pdfDocument {
    self = [super init];
    if (self) {
        _document = pdfDocument;
        _parsingQueue = dispatch_queue_create("EPPDFOutlineParsingQueue", 0);
    }
    return self;
}

- (NSArray *)outlineItems {
    
    dispatch_sync(_parsingQueue, ^{
        
        if (!_outlineItems) {
            EPPDFOutlineItem *rootItem = nil;
            CGPDFDictionaryRef docCatalog;
            docCatalog = CGPDFDocumentGetCatalog(_document);
            CGPDFDictionaryRef docOutlines;
            if (CGPDFDictionaryGetDictionary (docCatalog, "Outlines", &docOutlines)){
                rootItem = [self parseOutlineInDic:docOutlines parentItem:nil];
            }
            _outlineItems = rootItem ? rootItem.children : @[];
        }
    });
    
    return _outlineItems;
}

#pragma mark -
#pragma mark Data

- (CGPDFDictionaryRef)destsDictionary {
    
	if (!_destDic) {
		CGPDFDictionaryRef docCatalog;
		docCatalog = CGPDFDocumentGetCatalog(_document);
		if (CGPDFDictionaryGetDictionary (docCatalog, "Dests", &_destDic)) {
			return _destDic;
		}
	}
	return _destDic;
}

-(NSDictionary *)pageDataDictionary{
    
    if (!_pageDataDictionary) {
        CGPDFDictionaryRef nameDic, nameTree;
        CGPDFDictionaryRef docCatalog;
		docCatalog = CGPDFDocumentGetCatalog(_document);
		CGPDFDictionaryGetDictionary (docCatalog, "Names", &nameDic);
        CGPDFDictionaryGetDictionary (nameDic, "Dests", &nameTree);
        NSMutableDictionary *pageDic = [[NSMutableDictionary alloc] init];
        [self getPageNumberForNameNode:nameTree toDictionary:pageDic];
        _pageDataDictionary = [[NSDictionary alloc] initWithDictionary:pageDic];
    }
	return _pageDataDictionary;
}

-(NSUInteger)pageIndexForPageName:(NSString *)pageNameString{
	return [self pageIndexForPageName:pageNameString inPageNamesDictionary:[self pageDataDictionary]];
}

-(NSUInteger)pageIndexForPageName:(NSString *)pageNameString inPageNamesDictionary:(NSDictionary *)pageNames{
	return [[pageNames objectForKey:pageNameString] unsignedIntegerValue];
}

-(NSUInteger)pageIndexForObjectName:(const char *)name{
	CGPDFDictionaryRef destsDic = [self destsDictionary];
	CGPDFObjectRef destObject;
	if(CGPDFDictionaryGetObject(destsDic, name, &destObject)) {		
		CGPDFArrayRef destArray;
		CGPDFDictionaryRef destDict;
		switch (CGPDFObjectGetType(destObject)) {
			case kCGPDFObjectTypeDictionary: {
				if(CGPDFObjectGetValue(destObject, kCGPDFObjectTypeDictionary, &destDict)){
                    if (CGPDFDictionaryGetArray(destDict, "D", &destArray)) {
                        return [self pageIndexInDestinationArray:destArray];
					}
				}
			} break;
			case kCGPDFObjectTypeArray:
			{
				if(CGPDFObjectGetValue(destObject, kCGPDFObjectTypeArray, &destArray)){
                    return [self pageIndexInDestinationArray:destArray];
				}
			} break;
            default:
                break;
        }
	}
	return 0;
}

-(NSArray *)pageIndexData{
    
    if (!_pageIndexData) {
        NSMutableArray *pageIndexArray = [[NSMutableArray alloc] init];
        [pageIndexArray addObject:[NSNull null]];
        for (int checkPageNumber = 1;
             checkPageNumber < CGPDFDocumentGetNumberOfPages(_document) + 1;
             checkPageNumber++) {
            CGPDFPageRef checkPage = CGPDFDocumentGetPage(_document, checkPageNumber);
            CGPDFDictionaryRef checkPageObj = CGPDFPageGetDictionary(checkPage);
            NSValue *pageObjPointerValue = [NSValue valueWithPointer:checkPageObj];
            [pageIndexArray addObject:pageObjPointerValue];
        }
        _pageIndexData = [[NSArray alloc] initWithArray:pageIndexArray];
    }
    
	return _pageIndexData;
}

-(NSUInteger)pageIndexForPageObject:(CGPDFDictionaryRef)pageObj {
	NSArray *checkData = [self pageIndexData];
	for (int checkIndex = 1; checkIndex < [checkData count]; checkIndex ++) {
		if (pageObj == [[checkData objectAtIndex:checkIndex] pointerValue]) {
			return checkIndex;
		}
	}
	return 0;
}

-(void)getPageNumberForNameNode:(CGPDFDictionaryRef)nameNode toDictionary:(NSMutableDictionary *)pageDataDic{
	CGPDFArrayRef namesArray;
	if (CGPDFDictionaryGetArray(nameNode, "Names", &namesArray)) {

		for (NSUInteger index = 0; index < CGPDFArrayGetCount(namesArray); index += 2) {
			CGPDFStringRef nameKey;
			if (CGPDFArrayGetString(namesArray, index, &nameKey)){
				CGPDFObjectRef gotoObject;
				if (CGPDFArrayGetObject(namesArray, index + 1, &gotoObject)) {
					
					switch (CGPDFObjectGetType(gotoObject)) {
							
						case kCGPDFObjectTypeDictionary: {
							CGPDFArrayRef destArray;
							CGPDFDictionaryRef gotoDic;
							if (CGPDFObjectGetValue(gotoObject, kCGPDFObjectTypeDictionary, &gotoDic)){
                                
                                if (CGPDFDictionaryGetArray(gotoDic, "D", &destArray)) {
                                    [pageDataDic setValue:@([self pageIndexInDestinationArray:destArray])
                                                   forKey:(__bridge NSString *)CGPDFStringCopyTextString(nameKey)];
                                }
							}
						} break;
							
						case kCGPDFObjectTypeArray: {
							CGPDFArrayRef gotoArray;
							if (CGPDFObjectGetValue(gotoObject, kCGPDFObjectTypeArray, &gotoArray)){
                                
                                [pageDataDic setValue:@([self pageIndexInDestinationArray:gotoArray])
                                               forKey:(__bridge NSString *)CGPDFStringCopyTextString(nameKey)];
							}
						} break;
						case kCGPDFObjectTypeInteger:{
						}
							break;
						default:
							break;
					}
				}
			}
		}//end of for Loop.
	} //end of check "Names"
    
	CGPDFArrayRef kidsArray;
	if (CGPDFDictionaryGetArray(nameNode, "Kids", &kidsArray)) {
		for (int checkIndex = 0; checkIndex < CGPDFArrayGetCount(kidsArray); checkIndex++) {
			CGPDFDictionaryRef kidDic;
			if (CGPDFArrayGetDictionary(kidsArray, checkIndex, &kidDic)) {
				[self getPageNumberForNameNode:kidDic toDictionary:pageDataDic];
			}
		}
	}
}

- (NSUInteger)pageIndexInDestinationArray:(CGPDFArrayRef)destArray {
    
    NSUInteger pageIndex = NSNotFound;
    //int count = CGPDFArrayGetCount(destArray);
    CGPDFObjectRef ADestObject;
    
    if(CGPDFArrayGetObject(destArray, 0, &ADestObject)) {
        
        switch (CGPDFObjectGetType(ADestObject)) {
            case kCGPDFObjectTypeString: {
                CGPDFStringRef ADestString;
                if (CGPDFObjectGetValue(ADestObject, kCGPDFObjectTypeString, &ADestString)){
                    pageIndex = [self pageIndexForPageName:(__bridge NSString *)CGPDFStringCopyTextString(ADestString)];
                }
            } break;
                
            case kCGPDFObjectTypeArray: {
                CGPDFArrayRef ADestArray;
                if (CGPDFObjectGetValue(ADestObject, kCGPDFObjectTypeArray, &ADestArray)){
                    CGPDFDictionaryRef gotoPageObj;
                    if (CGPDFArrayGetDictionary(ADestArray, 0, &gotoPageObj)) {
                        pageIndex = [self pageIndexForPageObject:gotoPageObj];
                    }
                }
                
            } break;
            case  kCGPDFObjectTypeDictionary: {
                CGPDFDictionaryRef ADestGotoPageObj;
                if (CGPDFObjectGetValue(ADestObject, kCGPDFObjectTypeDictionary, &ADestGotoPageObj)){
                    pageIndex = [self pageIndexForPageObject:ADestGotoPageObj];
                }
            } break;
                
            default:
                break;
        }
    }
	return pageIndex;
}

#pragma mark -
#pragma mark Outline Parsing

- (EPPDFOutlineItem *)parseOutlineInDic:(CGPDFDictionaryRef)outlineDic parentItem:(EPPDFOutlineItem *)parentItem {

    EPPDFOutlineItem *item = [EPPDFOutlineItem item];

    // Title
    CGPDFStringRef title;
    if(CGPDFDictionaryGetString(outlineDic, "Title", &title)) {
		NSString *titleString =  (__bridge NSString *)CGPDFStringCopyTextString(title);
        item.title = titleString;
    }
    
    // level
    item.level = parentItem.level + 1;
    
    // Sliblings
    if (parentItem) {
        [parentItem addChildItem:item];
		// Next
        CGPDFDictionaryRef nextDic;
        if (CGPDFDictionaryGetDictionary(outlineDic, "Next", &nextDic)) {
            [self parseOutlineInDic:nextDic parentItem:parentItem];
        }
    }
	
    // Child
    CGPDFDictionaryRef firstDic;	
    if (CGPDFDictionaryGetDictionary(outlineDic, "First", &firstDic)) {
        [self parseOutlineInDic:firstDic parentItem:item];
    }
  	
	// Item Destination
	CGPDFObjectRef destObject;
	if(CGPDFDictionaryGetObject(outlineDic, "Dest", &destObject)) {
        
		switch (CGPDFObjectGetType(destObject)) {
			case kCGPDFObjectTypeString: {
				CGPDFStringRef destString;
				if (CGPDFObjectGetValue(destObject, kCGPDFObjectTypeString, &destString)){
					item.pageIndex = [self pageIndexForPageName:(__bridge NSString *)CGPDFStringCopyTextString(destString)];
				}
			} break;
			case kCGPDFObjectTypeArray: {
				CGPDFArrayRef destArray;
				if (CGPDFObjectGetValue(destObject, kCGPDFObjectTypeArray, &destArray)) {
					CGPDFDictionaryRef gotoPageObj;
					if (CGPDFArrayGetDictionary(destArray, 0, &gotoPageObj)) {
						item.pageIndex = [self pageIndexForPageObject:gotoPageObj];
					}
				}
			} break;
			case kCGPDFObjectTypeName: {
				const char * name;
				if(CGPDFObjectGetValue(destObject, kCGPDFObjectTypeName, &name)) {
					item.pageIndex = [self pageIndexForObjectName:name];
                }
            } break;
			default:
				break;
		}
	}
	else {
        CGPDFDictionaryRef ActionDic;
        if (CGPDFDictionaryGetDictionary(outlineDic, "A", &ActionDic)) {
            const char* pchS;
            if (CGPDFDictionaryGetName(ActionDic, "S", &pchS)) {
				if(!strcmp(pchS,"GoTo")) {
					CGPDFObjectRef destObj;
					if (CGPDFDictionaryGetObject(ActionDic, "D", &destObj)) {
						switch (CGPDFObjectGetType(destObj)) {
							case kCGPDFObjectTypeArray: {
								CGPDFArrayRef destArray;
								CGPDFObjectGetValue(destObj, kCGPDFObjectTypeArray, &destArray);
                                item.pageIndex = [self pageIndexInDestinationArray:destArray];
							} break;
							case kCGPDFObjectTypeString: {
								CGPDFStringRef destString;
								if (CGPDFObjectGetValue(destObj, kCGPDFObjectTypeString, &destString)) {
									item.pageIndex = [self pageIndexForPageName:(__bridge NSString *)CGPDFStringCopyTextString(destString)];
								}
							} break;
							default:
								break;
						}
						
					}
				}//end of if strcmp "GoTo"
			}//end of dicGetName
        }//end of dicGetActionDic
    }//end of else
    return item;
}

@end

@implementation EPPDFOutlineItem

+ (instancetype)item {
    return [[self alloc] init];
}

- (NSArray *)children {
    return [NSArray arrayWithArray:self.childrenItems];
}

- (void)addChildItem:(EPPDFOutlineItem *)childItem {
    if (!_childrenItems) {
        _childrenItems = @[].mutableCopy;
    }
    [self.childrenItems addObject:childItem];
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString string];
    for (NSUInteger i = 0; i < self.level; i ++) {
        [desc appendString:@"\t"];
    }
    [desc appendFormat:@"%@ : %d", self.title, self.pageIndex];
    
    for (EPPDFOutlineItem *childItem in self.childrenItems) {
        [desc appendFormat:@"\n%@", [childItem description]];
    }
    return desc;
}



@end