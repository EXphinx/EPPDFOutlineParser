//
//  EPPDFOutlineParser.h
//  EPPDFOutlineParsing
//
//  Created by EXphinx on 13-10-12.
//  Copyright (c) 2013年 EXphinx. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EPPDFOutlineParser : NSObject

- (id)initWithPDFDocument:(CGPDFDocumentRef)pdfDocument;

// perform parsing and get results.
- (NSArray *)outlineItems;

@end

@interface EPPDFOutlineItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSUInteger pageIndex;
@property (nonatomic, assign) NSUInteger level;

@property (nonatomic, strong, readonly) NSArray *children;

@end